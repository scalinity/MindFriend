-- =====================================================================================================================
-- Migration: 20260128160000_add_content_translations.sql
-- Description: Add Spanish and Portuguese-Brazil translations for programs
-- Date: 2026-01-28
-- =====================================================================================================================

BEGIN;

-- =====================================================================================================================
-- MARK: - Helper function to insert translations
-- =====================================================================================================================

CREATE OR REPLACE FUNCTION insert_program_translation(
  p_slug text,
  p_language_code text,
  p_title text,
  p_description text DEFAULT NULL
) RETURNS void AS $$
DECLARE
  v_content_id uuid;
BEGIN
  SELECT id INTO v_content_id FROM programs WHERE slug = p_slug;

  IF v_content_id IS NULL THEN
    RAISE NOTICE 'Program not found with slug: %', p_slug;
    RETURN;
  END IF;

  -- Insert or update translation
  INSERT INTO content_translations (
    content_type, content_id, language_code, title, description, is_verified
  ) VALUES (
    'program'::content_type_enum, v_content_id, p_language_code, p_title, p_description, true
  )
  ON CONFLICT (content_type, content_id, language_code) 
  DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    is_verified = true,
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- =====================================================================================================================
-- MARK: - Program Translations - Spanish (es)
-- =====================================================================================================================

-- CBT Programs
SELECT insert_program_translation('cbt-anxiety-7day', 'es',
  'Superando la Ansiedad con TCC',
  'Aprende técnicas de Terapia Cognitivo-Conductual basadas en evidencia para manejar la ansiedad generalizada. Este programa de 7 días te enseña a identificar patrones de pensamiento ansioso, desafiar distorsiones cognitivas y construir herramientas prácticas para una calma duradera.'
);

SELECT insert_program_translation('cbt-depression-14day', 'es',
  'TCC para la Depresión',
  'Programa de Terapia Cognitivo-Conductual basado en evidencia para manejar la depresión. Aprende activación conductual, desafío de pensamientos y habilidades de resolución de problemas para mejorar tu estado de ánimo y recuperar la motivación en 14 días estructurados.'
);

SELECT insert_program_translation('cbt-stress-7day', 'es',
  'Manejo del Estrés con TCC',
  'Domina técnicas de Terapia Cognitivo-Conductual para el manejo del estrés. Aprende a identificar desencadenantes de estrés, desafiar pensamientos catastróficos y desarrollar estrategias de afrontamiento saludables en este programa de 7 días.'
);

SELECT insert_program_translation('cbt-sleep-14day', 'es',
  'TCC para el Insomnio',
  'Programa clínicamente probado de Terapia Cognitivo-Conductual para el Insomnio (TCC-I). Mejora la calidad del sueño sin medicación mediante control de estímulos, restricción del sueño y reestructuración cognitiva.'
);

SELECT insert_program_translation('cbt-self-esteem-21day', 'es',
  'Construyendo Autoestima con TCC',
  'Programa integral de 21 días para desarrollar una autoestima saludable utilizando técnicas de TCC. Identifica y desafía creencias negativas sobre ti mismo, practica la autocompasión y construye confianza.'
);

SELECT insert_program_translation('cbt-panic-14day', 'es',
  'Superando el Pánico con TCC',
  'Programa especializado de TCC para el trastorno de pánico. Aprende a entender los ataques de pánico, manejar las sensaciones físicas e interrumpir el ciclo del miedo mediante exposición gradual.'
);

-- DBT Programs
SELECT insert_program_translation('dbt-emotion-regulation-21day', 'es',
  'Regulación Emocional DBT',
  'Aprende las poderosas habilidades de regulación emocional de la Terapia Dialéctico-Conductual. Este programa de 21 días te enseña a entender, nombrar y manejar emociones intensas de manera efectiva.'
);

SELECT insert_program_translation('dbt-distress-tolerance-14day', 'es',
  'Tolerancia al Malestar DBT',
  'Desarrolla resiliencia con habilidades de tolerancia al malestar de DBT. Aprende técnicas de crisis, auto-calmado y aceptación radical para navegar momentos difíciles.'
);

SELECT insert_program_translation('dbt-interpersonal-21day', 'es',
  'Efectividad Interpersonal DBT',
  'Mejora tus relaciones con habilidades interpersonales de DBT. Aprende a comunicar necesidades, establecer límites y mantener el respeto propio en las interacciones.'
);

SELECT insert_program_translation('dbt-mindfulness-14day', 'es',
  'Mindfulness DBT',
  'Desarrolla conciencia plena con las habilidades de mindfulness fundamentales de DBT. Practica la observación sin juicio, participación efectiva y vivir en el momento presente.'
);

-- ACT Programs
SELECT insert_program_translation('act-values-14day', 'es',
  'Viviendo tus Valores con ACT',
  'Descubre qué realmente te importa y alinea tus acciones con tus valores usando la Terapia de Aceptación y Compromiso. Este programa de 14 días te ayuda a crear una vida significativa.'
);

SELECT insert_program_translation('act-acceptance-21day', 'es',
  'Aceptación y Defusión ACT',
  'Aprende a relacionarte de manera diferente con pensamientos y sentimientos difíciles. Practica la aceptación, defusión cognitiva y flexibilidad psicológica.'
);

SELECT insert_program_translation('act-committed-action-14day', 'es',
  'Acción Comprometida ACT',
  'Transforma tus valores en acciones concretas. Aprende a establecer metas significativas, superar barreras y tomar pasos consistentes hacia lo que importa.'
);

-- MBCT Programs
SELECT insert_program_translation('mbct-depression-prevention-21day', 'es',
  'MBCT para Prevención de Recaídas',
  'Terapia Cognitiva Basada en Mindfulness para prevenir recaídas de depresión. Aprende a relacionarte de manera diferente con pensamientos depresivos y desarrolla prácticas de conciencia plena.'
);

SELECT insert_program_translation('mbct-stress-14day', 'es',
  'Mindfulness para el Estrés',
  'Reduce el estrés con prácticas de MBCT. Desarrolla conciencia del momento presente, autocompasión y respuestas más sabias a los desafíos de la vida.'
);

-- =====================================================================================================================
-- MARK: - Program Translations - Portuguese-Brazil (pt-BR)
-- =====================================================================================================================

-- CBT Programs
SELECT insert_program_translation('cbt-anxiety-7day', 'pt-BR',
  'Superando a Ansiedade com TCC',
  'Aprenda técnicas de Terapia Cognitivo-Comportamental baseadas em evidências para gerenciar a ansiedade generalizada. Este programa de 7 dias ensina você a identificar padrões de pensamento ansioso, desafiar distorções cognitivas e construir ferramentas práticas para uma calma duradoura.'
);

SELECT insert_program_translation('cbt-depression-14day', 'pt-BR',
  'TCC para Depressão',
  'Programa de Terapia Cognitivo-Comportamental baseado em evidências para gerenciar a depressão. Aprenda ativação comportamental, desafio de pensamentos e habilidades de resolução de problemas para melhorar seu humor e recuperar a motivação em 14 dias estruturados.'
);

SELECT insert_program_translation('cbt-stress-7day', 'pt-BR',
  'Gerenciamento do Estresse com TCC',
  'Domine técnicas de Terapia Cognitivo-Comportamental para gerenciamento do estresse. Aprenda a identificar gatilhos de estresse, desafiar pensamentos catastróficos e desenvolver estratégias de enfrentamento saudáveis neste programa de 7 dias.'
);

SELECT insert_program_translation('cbt-sleep-14day', 'pt-BR',
  'TCC para Insônia',
  'Programa clinicamente comprovado de Terapia Cognitivo-Comportamental para Insônia (TCC-I). Melhore a qualidade do sono sem medicação através de controle de estímulos, restrição de sono e reestruturação cognitiva.'
);

SELECT insert_program_translation('cbt-self-esteem-21day', 'pt-BR',
  'Construindo Autoestima com TCC',
  'Programa abrangente de 21 dias para desenvolver autoestima saudável usando técnicas de TCC. Identifique e desafie crenças negativas sobre si mesmo, pratique autocompaixão e construa confiança.'
);

SELECT insert_program_translation('cbt-panic-14day', 'pt-BR',
  'Superando o Pânico com TCC',
  'Programa especializado de TCC para transtorno de pânico. Aprenda a entender os ataques de pânico, gerenciar sensações físicas e interromper o ciclo do medo através de exposição gradual.'
);

-- DBT Programs
SELECT insert_program_translation('dbt-emotion-regulation-21day', 'pt-BR',
  'Regulação Emocional DBT',
  'Aprenda as poderosas habilidades de regulação emocional da Terapia Comportamental Dialética. Este programa de 21 dias ensina você a entender, nomear e gerenciar emoções intensas de forma eficaz.'
);

SELECT insert_program_translation('dbt-distress-tolerance-14day', 'pt-BR',
  'Tolerância ao Sofrimento DBT',
  'Desenvolva resiliência com habilidades de tolerância ao sofrimento da DBT. Aprenda técnicas de crise, autocalmante e aceitação radical para navegar momentos difíceis.'
);

SELECT insert_program_translation('dbt-interpersonal-21day', 'pt-BR',
  'Eficácia Interpessoal DBT',
  'Melhore seus relacionamentos com habilidades interpessoais da DBT. Aprenda a comunicar necessidades, estabelecer limites e manter o autorrespeito nas interações.'
);

SELECT insert_program_translation('dbt-mindfulness-14day', 'pt-BR',
  'Mindfulness DBT',
  'Desenvolva consciência plena com as habilidades fundamentais de mindfulness da DBT. Pratique observação sem julgamento, participação efetiva e viver no momento presente.'
);

-- ACT Programs
SELECT insert_program_translation('act-values-14day', 'pt-BR',
  'Vivendo seus Valores com ACT',
  'Descubra o que realmente importa para você e alinhe suas ações com seus valores usando a Terapia de Aceitação e Compromisso. Este programa de 14 dias ajuda você a criar uma vida significativa.'
);

SELECT insert_program_translation('act-acceptance-21day', 'pt-BR',
  'Aceitação e Desfusão ACT',
  'Aprenda a se relacionar de forma diferente com pensamentos e sentimentos difíceis. Pratique aceitação, desfusão cognitiva e flexibilidade psicológica.'
);

SELECT insert_program_translation('act-committed-action-14day', 'pt-BR',
  'Ação Comprometida ACT',
  'Transforme seus valores em ações concretas. Aprenda a estabelecer metas significativas, superar barreiras e dar passos consistentes em direção ao que importa.'
);

-- MBCT Programs
SELECT insert_program_translation('mbct-depression-prevention-21day', 'pt-BR',
  'MBCT para Prevenção de Recaídas',
  'Terapia Cognitiva Baseada em Mindfulness para prevenir recaídas de depressão. Aprenda a se relacionar de forma diferente com pensamentos depressivos e desenvolva práticas de consciência plena.'
);

SELECT insert_program_translation('mbct-stress-14day', 'pt-BR',
  'Mindfulness para o Estresse',
  'Reduza o estresse com práticas de MBCT. Desenvolva consciência do momento presente, autocompaixão e respostas mais sábias aos desafios da vida.'
);

-- =====================================================================================================================
-- MARK: - Additional Featured Programs (Welcome Journey, Gratitude, etc.)
-- =====================================================================================================================

-- These are the programs visible on the Programs tab that need translation
SELECT insert_program_translation('welcome-journey-7day', 'es',
  'Viaje de Bienvenida de 7 Días',
  'Tu introducción a MindFriend. Explora las herramientas principales y establece hábitos de bienestar en una semana.'
);
SELECT insert_program_translation('welcome-journey-7day', 'pt-BR',
  'Jornada de Boas-Vindas de 7 Dias',
  'Sua introdução ao MindFriend. Explore as ferramentas principais e estabeleça hábitos de bem-estar em uma semana.'
);

SELECT insert_program_translation('gratitude-practice-7day', 'es',
  'Práctica de Gratitud de 7 Días',
  'Desarrolla una práctica diaria de gratitud para aumentar el bienestar y cambiar tu perspectiva.'
);
SELECT insert_program_translation('gratitude-practice-7day', 'pt-BR',
  'Prática de Gratidão de 7 Dias',
  'Desenvolva uma prática diária de gratidão para aumentar o bem-estar e mudar sua perspectiva.'
);

SELECT insert_program_translation('mindfulness-foundations-14day', 'es',
  'Fundamentos de Mindfulness de 14 Días',
  'Construye una base sólida en mindfulness con prácticas guiadas diarias y técnicas de meditación.'
);
SELECT insert_program_translation('mindfulness-foundations-14day', 'pt-BR',
  'Fundamentos de Mindfulness de 14 Dias',
  'Construa uma base sólida em mindfulness com práticas guiadas diárias e técnicas de meditação.'
);

SELECT insert_program_translation('anxiety-reset-21day', 'es',
  'Reinicio de Ansiedad de 21 Días',
  'Un programa integral para transformar tu relación con la ansiedad y construir resiliencia duradera.'
);
SELECT insert_program_translation('anxiety-reset-21day', 'pt-BR',
  'Reinício da Ansiedade de 21 Dias',
  'Um programa abrangente para transformar sua relação com a ansiedade e construir resiliência duradoura.'
);

-- =====================================================================================================================
-- MARK: - Cleanup
-- =====================================================================================================================

DROP FUNCTION IF EXISTS insert_program_translation(text, text, text, text);

COMMIT;
