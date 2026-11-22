-- Text size gets two smaller steps (owner decision D46): 85%, 92%, 100%, 110%, 120%.
-- The check widens to 0.8–1.8 so no saved row has to change; the app shows a value above 1.2 as 120%.
alter table public.devices drop constraint devices_text_scale_check;
alter table public.devices add constraint devices_text_scale_check check (text_scale between 0.8 and 1.8);
comment on column public.devices.text_scale is 'text size multiplier on the phone''s own size, 1.0 = normal; from 0.8 to 1.8; the app offers 0.85, 0.92, 1.0, 1.1, 1.2; default 1.0';
