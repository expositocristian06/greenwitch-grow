-- =====================================================================
-- Green Witch Grow · Entrega elegida en cada pedido
-- YA APLICADO en Supabase el 12 nov 2026. Queda acá como registro.
-- La Edge Function create-preference guarda delivery_method y delivery_cp.
-- =====================================================================
alter table public.orders
  add column if not exists delivery_method text,
  add column if not exists delivery_cp text;

do $$ begin
  alter table public.orders add constraint orders_delivery_ok check (
    (delivery_method is null or delivery_method in ('retiro','coordinar','correo')) and
    (delivery_cp is null or delivery_cp ~ '^[1-9][0-9]{3}$')
  );
exception when duplicate_object then null; end $$;
