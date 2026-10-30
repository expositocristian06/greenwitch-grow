-- =====================================================================
-- Green Witch Grow · Endurecimiento de permisos (RLS + Storage)
-- Pegar entero en Supabase → SQL Editor → Run. Se puede correr varias veces.
--
-- Qué hace:
--   1. products     → el público solo ve productos ACTIVOS; solo el admin escribe.
--   2. orders → se agrega que el admin pueda BORRAR pedidos (el resto no se toca;
--      la Edge Function de pago escribe con service_role).
--   3. Bucket "products" → solo el admin sube/cambia/borra fotos; el público ya no
--      puede LISTAR el bucket (las fotos se siguen viendo por su URL pública).
--   4. Limita el bucket a imágenes de hasta 5 MB.
--
-- Requiere la función public.is_admin() que ya usa el panel.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.is_admin()') is null then
    raise exception 'Falta la función public.is_admin(). No se aplicó nada.';
  end if;
end $$;

-- ---------- Borrar políticas viejas (para no dejar ninguna abierta) ----------
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname from pg_policies
    where schemaname = 'public' and tablename = 'products'
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  for r in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (coalesce(qual,'') ilike '%products%' or coalesce(with_check,'') ilike '%products%')
  loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;

-- ---------- products ----------
alter table public.products enable row level security;

create policy "publico ve productos activos" on public.products
  for select to anon, authenticated
  using (active = true or public.is_admin());

create policy "admin crea productos" on public.products
  for insert to authenticated with check (public.is_admin());

create policy "admin edita productos" on public.products
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "admin borra productos" on public.products
  for delete to authenticated using (public.is_admin());

-- Precios y stock nunca negativos (NOT VALID: no revisa filas viejas, solo nuevas)
do $$ begin
  alter table public.products add constraint products_price_ok check (price >= 0) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.products add constraint products_stock_ok check (stock >= 0) not valid;
exception when duplicate_object then null; end $$;

-- ---------- Storage: bucket products ----------
update storage.buckets
   set file_size_limit = 5242880,
       allowed_mime_types = array['image/webp','image/jpeg','image/png','image/gif','image/avif']
 where id = 'products';

create policy "admin lee archivos de products" on storage.objects
  for select to authenticated using (bucket_id = 'products' and public.is_admin());
create policy "admin sube fotos" on storage.objects
  for insert to authenticated with check (bucket_id = 'products' and public.is_admin());
create policy "admin cambia fotos" on storage.objects
  for update to authenticated using (bucket_id = 'products' and public.is_admin())
  with check (bucket_id = 'products' and public.is_admin());
create policy "admin borra fotos" on storage.objects
  for delete to authenticated using (bucket_id = 'products' and public.is_admin());

-- ---------- Pedidos: el admin puede borrarlos ----------
-- (los order_items se borran solos por ON DELETE CASCADE)
drop policy if exists "admin borra pedidos" on public.orders;
create policy "admin borra pedidos" on public.orders
  for delete to authenticated using (public.is_admin());

commit;

-- ---------- Para revisar cómo quedó ----------
select tablename, policyname, cmd, roles
from pg_policies
where (schemaname = 'public' and tablename in ('products','orders','order_items'))
   or (schemaname = 'storage' and tablename = 'objects')
order by tablename, cmd;
