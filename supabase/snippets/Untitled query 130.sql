grant select on public.drivers to authenticated;
grant select on public.rides to authenticated;

-- also needed if/when the driver-side app updates its own status,
-- or the passenger inserts/updates rides directly (not just via the RPC)
grant update on public.drivers to authenticated;
grant update on public.rides to authenticated;
grant insert on public.rides to authenticated;