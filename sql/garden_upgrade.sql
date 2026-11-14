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
  add column if not exists growth_bonus_seconds integer not null default 0;

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
