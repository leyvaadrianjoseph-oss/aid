-- Python Garden platform upgrade.
-- Run after sql/schema.sql and sql/seed.sql. This migration is additive.

alter table shop_items add column if not exists growth_seconds integer not null default 300;
alter table garden_plots
  add column if not exists growth_bonus_seconds integer not null default 0,
  add column if not exists last_watered_at timestamptz;

update shop_items
set growth_seconds = case sprite
  when 'sunflower' then 300
  when 'tulip' then 420
  when 'mushroom' then 360
  when 'cactus' then 600
  else growth_seconds
end
where kind = 'seed' and growth_seconds = 300;

create table if not exists garden_inventory (
  id bigserial primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  item_id integer not null references shop_items(id) on delete cascade,
  quantity integer not null default 0 check (quantity >= 0),
  unique (user_id, item_id)
);

create table if not exists garden_decor (
  id bigserial primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  area text not null check (area in ('fence','decor')),
  slot integer not null,
  item_id integer not null references shop_items(id),
  placed_at timestamptz not null default now(),
  unique (user_id, area, slot),
  check ((area = 'fence' and slot between 0 and 7) or (area = 'decor' and slot between 0 and 3))
);

create table if not exists garden_daily_purchases (
  user_id uuid not null references profiles(id) on delete cascade,
  purchase_date date not null,
  quantity integer not null default 0 check (quantity between 0 and 100),
  primary key (user_id, purchase_date)
);

alter table garden_inventory enable row level security;
alter table garden_decor enable row level security;
alter table garden_daily_purchases enable row level security;

create table if not exists xp_history (
  id bigserial primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  amount integer not null,
  source text not null,
  source_id integer,
  created_at timestamptz not null default now()
);
alter table xp_history enable row level security;
create index if not exists idx_xp_history_user_created
  on xp_history(user_id, created_at desc);

-- Move legacy tools and decorations out of plant beds without duplicating
-- rows already migrated by sql/garden_upgrade.sql.
insert into garden_inventory(user_id, item_id, quantity)
select gp.user_id, gp.item_id, count(*)::integer
from garden_plots gp
join shop_items si on si.id = gp.item_id
where si.kind = 'tool'
group by gp.user_id, gp.item_id
on conflict (user_id, item_id)
do update set quantity = garden_inventory.quantity + excluded.quantity;

delete from garden_plots gp
using shop_items si
where si.id = gp.item_id and si.kind = 'tool';

insert into garden_decor(user_id, area, slot, item_id)
select gp.user_id,
       case when si.sprite = 'fence' then 'fence' else 'decor' end,
       gp.slot,
       gp.item_id
from garden_plots gp
join shop_items si on si.id = gp.item_id
where si.kind = 'decor'
  and ((si.sprite = 'fence' and gp.slot between 0 and 7)
    or (si.sprite <> 'fence' and gp.slot between 0 and 3))
on conflict (user_id, area, slot) do nothing;

delete from garden_plots gp
using shop_items si
where si.id = gp.item_id
  and si.kind = 'decor'
  and ((si.sprite = 'fence' and gp.slot between 0 and 7)
    or (si.sprite <> 'fence' and gp.slot between 0 and 3))
  and exists (
    select 1 from garden_decor gd
    where gd.user_id = gp.user_id
      and gd.item_id = gp.item_id
      and gd.slot = gp.slot
      and gd.area = case when si.sprite = 'fence' then 'fence' else 'decor' end
  );

alter table toolbox_topics
  add column if not exists category text not null default 'Basics',
  add column if not exists difficulty text not null default 'Beginner',
  add column if not exists tags jsonb not null default '[]'::jsonb,
  add column if not exists syntax text,
  add column if not exists common_errors jsonb not null default '[]'::jsonb;

create index if not exists idx_lessons_chapter_order
  on lessons(chapter_id, sort_order, id);
create index if not exists idx_chapters_published_order
  on chapters(is_published, sort_order, id);
create index if not exists idx_user_progress_user_status
  on user_progress(user_id, status);
create index if not exists idx_user_progress_completed
  on user_progress(user_id, completed_at desc)
  where completed_at is not null;
create index if not exists idx_garden_plots_user_slot
  on garden_plots(user_id, slot);
create index if not exists idx_toolbox_topics_category_title
  on toolbox_topics(category, title);

-- Persist earned achievements for each account.
create unique index if not exists idx_user_achievements_user_achievement
  on user_achievements(user_id, achievement_id);

-- Additional progression milestones; title checks keep this safe to rerun.
insert into achievements(title, description, rule_key, threshold)
select v.title, v.description, v.rule_key, v.threshold
from (values
  ('Trail explorer', 'Complete 5 Adventure lessons', 'lessons_done', 5),
  ('Chapter climber', 'Complete 10 Adventure lessons', 'lessons_done', 10),
  ('Python pathfinder', 'Complete 20 Adventure lessons', 'lessons_done', 20),
  ('XP collector', 'Earn 500 XP', 'xp', 500),
  ('Code gardener', 'Earn 1000 XP', 'xp', 1000),
  ('Steady learner', 'Reach a 7 day learning streak', 'streak', 7),
  ('Dedicated learner', 'Reach a 14 day learning streak', 'streak', 14)
) as v(title, description, rule_key, threshold)
where not exists (select 1 from achievements a where lower(a.title) = lower(v.title));

-- Add useful topics without deleting or replacing existing entries.
insert into toolbox_topics(title, summary, example_code, unlock_lesson_id, category, difficulty, tags, syntax, common_errors)
select v.title, v.summary, v.example_code, v.unlock_lesson_id, v.category, v.difficulty, v.tags::jsonb, v.syntax, v.common_errors::jsonb
from (values
('Strings', 'Strings store text. Use quotes around text and join strings with + when needed.', 'name = "Sprout"\nprint("Hello, " + name)', null::integer, 'Data types', 'Beginner', '["text","quotes"]', 'text = "hello"', '["Forgetting quotes around text","Mixing text and numbers without converting"]'),
('Booleans', 'A Boolean is either True or False. Conditions use these values to make decisions.', 'is_sunny = True\nprint(is_sunny)', null::integer, 'Data types', 'Beginner', '["true","false","conditions"]', 'is_ready = True', '["Writing true instead of True","Using = when comparing values"]'),
('Comparisons', 'Comparison operators compare values and produce True or False.', 'water = 4\nprint(water >= 3)\nprint(water == 4)', null::integer, 'Operators', 'Beginner', '["comparison","operators"]', 'left == right', '["Using = instead of == for comparison"]'),
('while loops', 'A while loop repeats while its condition remains true. Make sure the condition eventually changes.', 'water = 3\nwhile water > 0:\n    print(water)\n    water -= 1', null::integer, 'Loops', 'Beginner', '["while","repetition"]', 'while condition:\n    statement', '["Forgetting to update the condition","Incorrect indentation"]'),
('Lists', 'Lists keep multiple values in order. Indexes start at zero.', 'plants = ["fern", "rose", "cactus"]\nprint(plants[0])\nprint(len(plants))', null::integer, 'Collections', 'Beginner', '["list","index","len"]', 'items = [value1, value2]', '["Using an index that does not exist","Forgetting commas between values"]'),
('List methods', 'Use append() to add an item and remove() to remove a matching item.', 'plants = ["fern", "rose"]\nplants.append("cactus")\nprint(plants)', null::integer, 'Collections', 'Beginner', '["append","remove"]', 'items.append(value)', '["Calling a method without parentheses"]'),
('Functions', 'Functions package reusable instructions. Define one with def, then call its name.', 'def greet(name):\n    print("Hello", name)\ngreet("Sprout")', null::integer, 'Functions', 'Beginner', '["def","parameters","call"]', 'def function_name(parameter):\n    statement', '["Forgetting the colon","Incorrect indentation","Defining a function but never calling it"]'),
('Return values', 'return sends a result back to the code that called a function.', 'def double(number):\n    return number * 2\nprint(double(4))', null::integer, 'Functions', 'Intermediate', '["return","result"]', 'return expression', '["Printing instead of returning when a value is needed"]'),
('Dictionaries', 'Dictionaries store key-value pairs. Use a key to look up its value.', 'plant = {"name": "Fern", "water": 3}\nprint(plant["name"])', null::integer, 'Collections', 'Intermediate', '["dict","key","value"]', 'data = {"key": value}', '["Looking up a key that does not exist","Forgetting the colon between key and value"]'),
('Modules', 'Modules let you reuse code from Python libraries with import.', 'import math\nprint(math.sqrt(25))', null::integer, 'Tools', 'Intermediate', '["import","math"]', 'import module_name', '["Misspelling the module name"]'),
('Exceptions', 'Use try and except to handle errors without stopping the whole program.', 'try:\n    number = int("12")\n    print(number)\nexcept ValueError:\n    print("Please enter a number")', null::integer, 'Errors', 'Intermediate', '["try","except","ValueError"]', 'try:\n    statement\nexcept ErrorType:\n    recovery', '["Catching the wrong exception type","Putting except before try"]'),
('File basics', 'Use with open() to work with files and close them automatically.', 'with open("notes.txt", "w") as file:\n    file.write("Hello garden")', null::integer, 'Tools', 'Intermediate', '["open","with","write"]', 'with open(path, mode) as file:', '["Using the wrong file mode","Forgetting that file paths depend on the working directory"]')
) as v(title, summary, example_code, unlock_lesson_id, category, difficulty, tags, syntax, common_errors)
where not exists (select 1 from toolbox_topics t where lower(t.title) = lower(v.title));


-- Atomic harvesting: verifies maturity and awards seeds/XP in the same transaction.
create or replace function garden_harvest(
  p_user_id uuid,
  p_item_id integer,
  p_slot integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plot_id bigint;
  v_planted_at timestamptz;
  v_bonus integer;
  v_growth_seconds integer;
  v_cost integer;
  v_kind text;
  v_elapsed integer;
  v_reward integer;
  v_new_seeds integer;
  v_new_xp integer;
begin
  if p_slot is null or p_slot < 0 or p_slot > 11 then
    raise exception 'Invalid plot';
  end if;

  select gp.id, gp.planted_at, coalesce(gp.growth_bonus_seconds, 0),
         greatest(60, coalesce(si.growth_seconds, 300)), si.cost_seeds, si.kind
  into v_plot_id, v_planted_at, v_bonus, v_growth_seconds, v_cost, v_kind
  from garden_plots gp
  join shop_items si on si.id = gp.item_id
  where gp.user_id = p_user_id
    and gp.slot = p_slot
    and gp.item_id = p_item_id
  for update of gp;

  if not found or v_kind <> 'seed' then
    raise exception 'Plant not found';
  end if;

  v_elapsed := floor(extract(epoch from (now() - v_planted_at)))::integer + v_bonus;
  if v_elapsed < v_growth_seconds then
    raise exception 'Plant is not mature yet';
  end if;

  v_reward := greatest(1, floor(v_cost * 0.75)::integer);

  update profiles
  set seeds = seeds + v_reward,
      xp = xp + 5
  where id = p_user_id
  returning seeds, xp into v_new_seeds, v_new_xp;

  if not found then
    raise exception 'Player profile not found';
  end if;

  insert into xp_history(user_id, amount, source, source_id)
  values (p_user_id, 5, 'garden_harvest', p_slot);

  delete from garden_plots where id = v_plot_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'harvest',
    'item_id', p_item_id,
    'slot', p_slot,
    'reward_seeds', v_reward,
    'reward_xp', 5,
    'seeds', v_new_seeds,
    'xp', v_new_xp
  );
end;
$$;

revoke all on function garden_harvest(uuid, integer, integer) from public, anon, authenticated;
grant execute on function garden_harvest(uuid, integer, integer) to service_role;


-- Move a placed decoration back into inventory atomically.
create or replace function garden_pickup_decor(
  p_user_id uuid,
  p_item_id integer,
  p_area text,
  p_slot integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_decor_id bigint;
  v_item_id integer;
  v_quantity integer;
begin
  if p_area not in ('fence', 'decor') then
    raise exception 'Invalid decoration area';
  end if;
  if (p_area = 'fence' and (p_slot < 0 or p_slot > 7))
     or (p_area = 'decor' and (p_slot < 0 or p_slot > 3)) then
    raise exception 'Invalid decoration slot';
  end if;

  select id, item_id into v_decor_id, v_item_id
  from garden_decor
  where user_id = p_user_id
    and item_id = p_item_id
    and area = p_area
    and slot = p_slot
  for update;

  if not found then
    raise exception 'Decoration not found';
  end if;

  insert into garden_inventory(user_id, item_id, quantity)
  values (p_user_id, v_item_id, 1)
  on conflict (user_id, item_id)
  do update set quantity = garden_inventory.quantity + 1
  returning quantity into v_quantity;

  delete from garden_decor where id = v_decor_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'pickup_decor',
    'item_id', v_item_id,
    'area', p_area,
    'slot', p_slot,
    'quantity', v_quantity
  );
end;
$$;

revoke all on function garden_pickup_decor(uuid, integer, text, integer) from public, anon, authenticated;
grant execute on function garden_pickup_decor(uuid, integer, text, integer) to service_role;


-- Seed stock is purchased into inventory in batches, then consumed when planted.
create or replace function garden_purchase(
  p_user_id uuid,
  p_item_id integer,
  p_quantity integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance integer;
  v_cost integer;
  v_kind text;
  v_active boolean;
  v_owned integer;
  v_today date := (now() at time zone 'Asia/Manila')::date;
  v_used integer;
  v_total_cost bigint;
  v_new_balance integer;
  v_new_quantity integer;
begin
  if p_quantity is null or p_quantity < 1 or p_quantity > 100 then
    raise exception 'Quantity must be between 1 and 100';
  end if;

  select seeds into v_balance
  from profiles where id = p_user_id for update;
  if not found then raise exception 'Player profile not found'; end if;

  select cost_seeds, kind, is_active
  into v_cost, v_kind, v_active
  from shop_items where id = p_item_id;
  if not found or v_active is distinct from true or v_kind is null then
    raise exception 'Item not available';
  end if;

  if v_kind = 'tool' then
    if p_quantity <> 1 then raise exception 'Tools can only be purchased one at a time'; end if;
    select quantity into v_owned from garden_inventory
    where user_id = p_user_id and item_id = p_item_id;
    if coalesce(v_owned, 0) > 0 then raise exception 'Already own this tool'; end if;
  end if;

  insert into garden_daily_purchases(user_id, purchase_date, quantity)
  values (p_user_id, v_today, 0)
  on conflict (user_id, purchase_date) do nothing;

  select quantity into v_used
  from garden_daily_purchases
  where user_id = p_user_id and purchase_date = v_today
  for update;
  if v_used + p_quantity > 100 then raise exception 'Daily purchase limit reached'; end if;

  v_total_cost := v_cost::bigint * p_quantity;
  if v_balance < v_total_cost then raise exception 'Not enough seeds'; end if;
  v_new_balance := v_balance - v_total_cost;

  update profiles set seeds = v_new_balance where id = p_user_id;

  insert into garden_inventory(user_id, item_id, quantity)
  values (p_user_id, p_item_id, p_quantity)
  on conflict (user_id, item_id)
  do update set quantity = garden_inventory.quantity + excluded.quantity
  returning quantity into v_new_quantity;

  update garden_daily_purchases
  set quantity = quantity + p_quantity
  where user_id = p_user_id and purchase_date = v_today;

  return jsonb_build_object(
    'ok', true, 'action', 'purchase', 'item_id', p_item_id,
    'quantity', p_quantity, 'inventory_quantity', v_new_quantity,
    'seeds', v_new_balance, 'daily_purchased', v_used + p_quantity,
    'daily_limit', 100
  );
end;
$$;

create or replace function garden_plant(
  p_user_id uuid,
  p_item_id integer,
  p_slot integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text;
  v_active boolean;
  v_quantity integer;
  v_remaining integer;
  v_balance integer;
begin
  if p_slot is null or p_slot < 0 or p_slot > 11 then
    raise exception 'Invalid plot';
  end if;

  select kind, is_active into v_kind, v_active
  from shop_items where id = p_item_id;
  if not found or v_active is distinct from true or v_kind <> 'seed' then
    raise exception 'Seed item not available';
  end if;

  if exists (select 1 from garden_plots where user_id = p_user_id and slot = p_slot) then
    raise exception 'Plot already planted';
  end if;

  select quantity into v_quantity
  from garden_inventory
  where user_id = p_user_id and item_id = p_item_id
  for update;
  if not found or coalesce(v_quantity, 0) < 1 then
    raise exception 'No seeds of this type in inventory';
  end if;

  insert into garden_plots(user_id, slot, item_id)
  values (p_user_id, p_slot, p_item_id);

  update garden_inventory
  set quantity = quantity - 1
  where user_id = p_user_id and item_id = p_item_id and quantity = v_quantity
  returning quantity into v_remaining;
  if not found then raise exception 'Inventory changed. Try again'; end if;

  select seeds into v_balance from profiles where id = p_user_id;
  return jsonb_build_object(
    'ok', true, 'action', 'plant', 'item_id', p_item_id,
    'slot', p_slot, 'inventory_quantity', v_remaining,
    'seeds', coalesce(v_balance, 0)
  );
end;
$$;

revoke all on function garden_purchase(uuid, integer, integer) from public, anon, authenticated;
revoke all on function garden_plant(uuid, integer, integer) from public, anon, authenticated;
grant execute on function garden_purchase(uuid, integer, integer) to service_role;
grant execute on function garden_plant(uuid, integer, integer) to service_role;


-- Record every Check click, including unsuccessful attempts.
create or replace function record_lesson_attempt(
  p_user_id uuid, p_lesson_id integer, p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attempts integer;
begin
  insert into user_progress(user_id, lesson_id, status, best_code, attempts)
  values (p_user_id, p_lesson_id, 'open', left(coalesce(p_code, ''), 5000), 1)
  on conflict (user_id, lesson_id)
  do update set
    attempts = coalesce(user_progress.attempts, 0) + 1,
    best_code = case when user_progress.status = 'done'
      then user_progress.best_code else excluded.best_code end
  returning attempts into v_attempts;
  return jsonb_build_object('ok', true, 'attempts', v_attempts);
end;
$$;

-- Completion and rewards are one transaction and can only be awarded once.
create or replace function complete_lesson(
  p_user_id uuid, p_lesson_id integer, p_code text,
  p_reward_seeds integer, p_reward_xp integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_seeds integer;
  v_xp integer;
  v_old_streak integer;
  v_streak integer;
  v_last timestamptz;
  v_last_day date;
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  if p_reward_seeds < 0 or p_reward_xp < 0 then raise exception 'Invalid lesson reward'; end if;

  select seeds, xp, streak into v_seeds, v_xp, v_old_streak
  from profiles where id = p_user_id for update;
  if not found then raise exception 'Player profile not found'; end if;

  select status into v_status from user_progress
  where user_id = p_user_id and lesson_id = p_lesson_id for update;

  if v_status = 'done' then
    update user_progress set best_code = left(coalesce(p_code, ''), 5000)
    where user_id = p_user_id and lesson_id = p_lesson_id;
    return jsonb_build_object('awarded', false, 'seeds', v_seeds, 'xp', v_xp, 'streak', v_old_streak);
  end if;

  select max(completed_at) into v_last from user_progress
  where user_id = p_user_id and status = 'done' and completed_at is not null;

  if v_last is null then
    v_streak := 1;
  else
    v_last_day := (v_last at time zone 'Asia/Manila')::date;
    if v_last_day = v_today then v_streak := greatest(1, v_old_streak);
    elsif v_last_day = v_today - 1 then v_streak := v_old_streak + 1;
    else v_streak := 1;
    end if;
  end if;

  insert into user_progress(user_id, lesson_id, status, best_code, completed_at)
  values (p_user_id, p_lesson_id, 'done', left(coalesce(p_code, ''), 5000), now())
  on conflict (user_id, lesson_id)
  do update set status = 'done', best_code = excluded.best_code,
                completed_at = coalesce(user_progress.completed_at, excluded.completed_at);

  update profiles set seeds = seeds + p_reward_seeds,
                      xp = xp + p_reward_xp, streak = v_streak
  where id = p_user_id
  returning seeds, xp into v_seeds, v_xp;

  insert into xp_history(user_id, amount, source, source_id)
  values (p_user_id, p_reward_xp, 'lesson', p_lesson_id);

  return jsonb_build_object('awarded', true, 'seeds', v_seeds, 'xp', v_xp, 'streak', v_streak);
end;
$$;

revoke all on function record_lesson_attempt(uuid, integer, text) from public, anon, authenticated;
revoke all on function complete_lesson(uuid, integer, text, integer, integer) from public, anon, authenticated;
grant execute on function record_lesson_attempt(uuid, integer, text) to service_role;
grant execute on function complete_lesson(uuid, integer, text, integer, integer) to service_role;


-- Combined garden loading RPC used by the PHP API.
create or replace function garden_load(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
select jsonb_build_object(
  'items', coalesce((select jsonb_agg(to_jsonb(si) order by si.cost_seeds, si.id) from shop_items si where si.is_active = true), '[]'::jsonb),
  'plots', coalesce((select jsonb_agg(to_jsonb(gp) order by gp.slot) from garden_plots gp where gp.user_id = p_user_id), '[]'::jsonb),
  'inventory', coalesce((select jsonb_agg(to_jsonb(gi) order by gi.item_id) from garden_inventory gi where gi.user_id = p_user_id), '[]'::jsonb),
  'decor', coalesce((select jsonb_agg(to_jsonb(gd) order by gd.area, gd.slot) from garden_decor gd where gd.user_id = p_user_id), '[]'::jsonb),
  'seeds', coalesce((select p.seeds from profiles p where p.id = p_user_id), 0),
  'daily_purchased', coalesce((select dp.quantity from garden_daily_purchases dp where dp.user_id = p_user_id and dp.purchase_date = (now() at time zone 'Asia/Manila')::date), 0),
  'daily_limit', 100
);
$$;

revoke all on function garden_load(uuid) from public, anon, authenticated;
grant execute on function garden_load(uuid) to service_role;

