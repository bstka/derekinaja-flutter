-- Generates 50 random drivers scattered within ~2.5km of the given point.
-- Center: lat -7.394520134375035, lng 110.2280184369884

insert into public.drivers (model, number, is_available, location)
select
    (array[
        'Ford F-350 Flatbed',
        'Isuzu Elf Tow Truck',
        'Mitsubishi Fuso Flatbed',
        'Hino Dutro Tow',
        'Toyota Dyna Flatbed',
        'Suzuki Carry Hook Tow'
    ])[floor(random() * 6 + 1)] as model,
    'B ' || (1000 + floor(random() * 8999))::int || ' ' ||
        (array['ABC','TOW','XYZ','DRK','FLB'])[floor(random() * 5 + 1)] as number,
    true as is_available,
    -- Random offset within roughly 2.5km radius.
    -- 0.0225 degrees latitude ≈ 2.5km; longitude scaled by cos(latitude) to keep it circular.
    st_geogfromtext(
        'POINT(' ||
        (110.2280184369884 + (random() - 0.5) * 0.045 / cos(radians(-7.394520134375035))) || ' ' ||
        (-7.394520134375035 + (random() - 0.5) * 0.045) ||
        ')'
    ) as location
from generate_series(1, 50);