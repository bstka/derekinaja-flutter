-- -7.395988216872493, 110.24056704681469

insert into public.drivers (id, model, number, location, is_available)
    values
    ('ab629987-a163-43eb-89cc-a0bdf6c9e39f', 'TOW TRUCK', 'GHI-789', ST_GeographyFromText('SRID=4326;POINT(110.24056704681469 -7.395988216872493)'), true);