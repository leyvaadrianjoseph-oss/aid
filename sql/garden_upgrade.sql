-- Safe, additive upgrade for the Inside the Garden features.
-- Run once in Supabase SQL Editor. Existing profiles, seeds and plots are preserved.

alter table shop_items add column if not exists growth_seconds integer not null default 300;
update shop_items set growth_seconds = case sprite
  when 'sunflower' then 300
  when 'tulip' then 420
  when 'mushroom' then 360
  when 'cactus' then 600
  else 300 end
where kind = 'seed';

alter table garden_plots
  add column if not exists growth_bonus_seconds integer not null default 0,
  add column if not exists last_watered_at timestamptz;

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

alter table garden_inventory enable row level security;
alter table garden_decor enable row level security;

-- Preserve items that older versions allowed users to place directly in plant plots.
-- Tools become owned inventory; decorations move to their dedicated spaces when a valid
-- destination is available. Any overflow remains visible in its original plot.
insert into garden_inventory (user_id, item_id, quantity)
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

insert into garden_decor (user_id, area, slot, item_id)
select user_id, area, slot, item_id
from (
  select gp.user_id, gp.item_id, gp.slot,
         case when si.sprite = 'fence' then 'fence' else 'decor' end as area
  from garden_plots gp
  join shop_items si on si.id = gp.item_id
  where si.kind = 'decor'
) legacy
where (area = 'fence' and slot between 0 and 7)
   or (area = 'decor' and slot between 0 and 3)
on conflict (user_id, area, slot) do nothing;

delete from garden_plots gp
using shop_items si
where si.id = gp.item_id
  and si.kind = 'decor'
  and ((si.sprite = 'fence' and gp.slot between 0 and 7)
    or (si.sprite <> 'fence' and gp.slot between 0 and 3));
