-- =========================================================
-- 1. Make sure RLS is enabled on both tables
-- =========================================================
alter table public.drivers enable row level security;
alter table public.rides enable row level security;

-- =========================================================
-- 2. DRIVERS table policies
-- =========================================================

-- Allow anyone signed in (including anonymous) to read driver rows.
-- This is what your `.stream()` subscription needs to receive updates.
drop policy if exists "Allow authenticated read access to drivers" on public.drivers;
create policy "Allow authenticated read access to drivers"
on public.drivers
for select
to authenticated
using (true);

-- If your `find_driver` RPC needs to UPDATE the driver's availability
-- (e.g. marking is_available = false once assigned), and it runs as
-- the calling user rather than a security definer function, you'll
-- also need an update policy. Skip this if find_driver is SECURITY DEFINER.
drop policy if exists "Allow drivers to update their own row" on public.drivers;
create policy "Allow drivers to update their own row"
on public.drivers
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- =========================================================
-- 3. RIDES table policies
-- =========================================================

-- Allow the passenger AND driver involved in a ride to read it
drop policy if exists "Allow ride participants to read their ride" on public.rides;
create policy "Allow ride participants to read their ride"
on public.rides
for select
to authenticated
using (
  auth.uid() = passenger_id
  or auth.uid() = driver_id
);

-- Allow the passenger to create a ride (if not done via a SECURITY DEFINER RPC)
drop policy if exists "Allow passenger to insert their own ride" on public.rides;
create policy "Allow passenger to insert their own ride"
on public.rides
for insert
to authenticated
with check (auth.uid() = passenger_id);

-- Allow the driver to update ride status (e.g. picking_up -> riding -> completed)
drop policy if exists "Allow driver to update ride status" on public.rides;
create policy "Allow driver to update ride status"
on public.rides
for update
to authenticated
using (auth.uid() = driver_id)
with check (auth.uid() = driver_id);

-- =========================================================
-- 4. Enable Realtime replication on both tables
-- =========================================================
-- alter publication supabase_realtime add table public.drivers;
-- alter publication supabase_realtime add table public.rides;