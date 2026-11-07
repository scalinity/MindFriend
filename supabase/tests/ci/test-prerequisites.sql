-- Fixture-only data/hook omitted by the public-only remote baseline dump.
-- Actual handle_new_user function is provided by repository migrations.
INSERT INTO public.supported_languages(code,name,native_name,is_active)
VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
