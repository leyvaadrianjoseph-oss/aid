-- Python Garden platform upgrade.
-- Additive only: preserves existing accounts, lessons, XP, seeds, progress and garden data.

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
