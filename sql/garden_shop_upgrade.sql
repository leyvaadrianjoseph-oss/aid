-- Faster garden loading and safe, server-enforced bulk purchases.
-- Run this once in the Supabase SQL Editor after garden_upgrade.sql.

create table if not exists garden_daily_purchases (
  user_id uuid not null references profiles(id) on delete cascade,
  purchase_date date not null,
  quantity integer not null default 0 check (quantity between 0 and 100),
  primary key (user_id, purchase_date)
);

alter table garden_daily_purchases enable row level security;

create or replace function garden_load(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(si) order by si.cost_seeds asc, si.id asc)
      from shop_items si
      where si.is_active = true
    ), '[]'::jsonb),
    'plots', coalesce((
      select jsonb_agg(to_jsonb(gp) order by gp.slot asc)
      from garden_plots gp
      where gp.user_id = p_user_id
    ), '[]'::jsonb),
    'inventory', coalesce((
      select jsonb_agg(to_jsonb(gi) order by gi.item_id asc)
      from garden_inventory gi
      where gi.user_id = p_user_id
    ), '[]'::jsonb),
    'decor', coalesce((
      select jsonb_agg(to_jsonb(gd) order by gd.area asc, gd.slot asc)
      from garden_decor gd
      where gd.user_id = p_user_id
    ), '[]'::jsonb),
    'seeds', coalesce((select p.seeds from profiles p where p.id = p_user_id), 0),
    'daily_purchased', coalesce((
      select dp.quantity
      from garden_daily_purchases dp
      where dp.user_id = p_user_id
        and dp.purchase_date = (now() at time zone 'Asia/Manila')::date
    ), 0),
    'daily_limit', 100
  );
$$;

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
begin
  if p_quantity is null or p_quantity < 1 or p_quantity > 100 then
    raise exception 'Quantity must be between 1 and 100';
  end if;

  select seeds into v_balance
  from profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'Player profile not found';
  end if;

  select cost_seeds, kind, is_active
  into v_cost, v_kind, v_active
  from shop_items
  where id = p_item_id;

  if not found or v_active is distinct from true or v_kind is null then
    raise exception 'Item not available';
  end if;

  if v_kind = 'seed' then
    raise exception 'Seeds are planted directly into an empty plot';
  end if;

  if v_kind = 'tool' then
    if p_quantity <> 1 then
      raise exception 'Tools can only be purchased one at a time';
    end if;

    select quantity into v_owned
    from garden_inventory
    where user_id = p_user_id and item_id = p_item_id;

    if coalesce(v_owned, 0) > 0 then
      raise exception 'Already own this tool';
    end if;
  end if;

  insert into garden_daily_purchases (user_id, purchase_date, quantity)
  values (p_user_id, v_today, 0)
  on conflict (user_id, purchase_date) do nothing;

  select quantity into v_used
  from garden_daily_purchases
  where user_id = p_user_id and purchase_date = v_today
  for update;

  if v_used + p_quantity > 100 then
    raise exception 'Daily purchase limit reached';
  end if;

  v_total_cost := v_cost::bigint * p_quantity;
  if v_balance < v_total_cost then
    raise exception 'Not enough seeds';
  end if;

  v_new_balance := v_balance - v_total_cost;

  update profiles
  set seeds = v_new_balance
  where id = p_user_id;

  insert into garden_inventory (user_id, item_id, quantity)
  values (p_user_id, p_item_id, p_quantity)
  on conflict (user_id, item_id)
  do update set quantity = garden_inventory.quantity + excluded.quantity;

  update garden_daily_purchases
  set quantity = quantity + p_quantity
  where user_id = p_user_id and purchase_date = v_today;

  return jsonb_build_object(
    'ok', true,
    'action', 'purchase',
    'item_id', p_item_id,
    'quantity', p_quantity,
    'seeds', v_new_balance,
    'daily_purchased', v_used + p_quantity,
    'daily_limit', 100
  );
end;
$$;

revoke all on function garden_load(uuid) from public, anon, authenticated;
revoke all on function garden_purchase(uuid, integer, integer) from public, anon, authenticated;
grant execute on function garden_load(uuid) to service_role;
grant execute on function garden_purchase(uuid, integer, integer) to service_role;
