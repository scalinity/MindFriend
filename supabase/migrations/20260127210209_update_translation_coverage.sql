-- Update translation coverage for Spanish and Portuguese-Brazil
-- These translations were completed on 2026-01-27

UPDATE public.supported_languages
SET translation_coverage = 100.00
WHERE code = 'es';

UPDATE public.supported_languages
SET translation_coverage = 100.00
WHERE code = 'pt-BR';
