-- Complete Spanish and Portuguese translations for cognitive distortions
-- This adds the missing 22 translation records (11 distortions × 2 languages)
-- Note: Table is created in later migration (20260701000004_cognitive_coach_schema.sql)

-- Get distortion IDs (we'll need these for the INSERT statements)
DO $$
BEGIN
  -- Only proceed if tables exist
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'cognitive_distortions'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'distortion_education'
  ) THEN
    -- Nested block for variable declarations
    DECLARE
      aon_id UUID;
      cat_id UUID;
      mind_id UUID;
      fort_id UUID;
      lab_id UUID;
      sho_id UUID;
      emf_id UUID;
      mins_id UUID;
      blame_id UUID;
      comp_id UUID;
      rg_id UUID;
      what_id UUID;
    BEGIN
  -- Fetch all distortion IDs
  SELECT id INTO aon_id FROM cognitive_distortions WHERE code = 'AON';
  SELECT id INTO cat_id FROM cognitive_distortions WHERE code = 'CAT';
  SELECT id INTO mind_id FROM cognitive_distortions WHERE code = 'MIND';
  SELECT id INTO fort_id FROM cognitive_distortions WHERE code = 'FORT';
  SELECT id INTO lab_id FROM cognitive_distortions WHERE code = 'LAB';
  SELECT id INTO sho_id FROM cognitive_distortions WHERE code = 'SHO';
  SELECT id INTO emf_id FROM cognitive_distortions WHERE code = 'EMF';
  SELECT id INTO mins_id FROM cognitive_distortions WHERE code = 'MINS';
  SELECT id INTO blame_id FROM cognitive_distortions WHERE code = 'BLAME';
  SELECT id INTO comp_id FROM cognitive_distortions WHERE code = 'COMP';
  SELECT id INTO rg_id FROM cognitive_distortions WHERE code = 'RG';
  SELECT id INTO what_id FROM cognitive_distortions WHERE code = 'WHAT';

  -- Spanish (es) translations
  INSERT INTO distortion_education (distortion_id, locale, name_translated, short_description_translated, full_description_translated, reframe_templates_translated, questions_translated) VALUES
  
  -- All-or-Nothing Thinking (Spanish)
  (aon_id, 'es', 'Pensamiento Todo o Nada', 
   'Ver las cosas en categorías blancas o negras',
   'El pensamiento todo o nada significa ver las situaciones en solo dos categorías en lugar de en un continuo.',
   ARRAY['La perfección no es posible. ¿Qué salió bien?', '¿Hay matices grises en esta situación?'],
   ARRAY['¿Qué evidencia tengo que apoya ambos lados?', '¿Estoy viendo esto en extremos?', '¿Cuál es el punto medio aquí?']),

  -- Catastrophizing (Spanish)
  (cat_id, 'es', 'Catastrofización',
   'Esperar el peor resultado posible',
   'La catastrofización es magnificar lo negativo y minimizar lo positivo, asumiendo que las cosas irán mal.',
   ARRAY['¿Qué es lo más probable que suceda?', '¿Cómo has manejado desafíos antes?'],
   ARRAY['¿Cuál es la evidencia real del peor escenario?', '¿Qué otros resultados son posibles?', '¿He sobrevivido situaciones similares antes?']),

  -- Mind Reading (Spanish)
  (mind_id, 'es', 'Lectura de Mentes',
   'Asumir que sabes lo que otros piensan',
   'La lectura de mentes es asumir que sabes lo que otros están pensando sin evidencia real.',
   ARRAY['No puedes saber lo que piensan sin preguntar', '¿Podrías estar proyectando tus propios miedos?'],
   ARRAY['¿Qué evidencia concreta tengo de lo que piensan?', '¿He preguntado directamente?', '¿Podría haber otras explicaciones?']),

  -- Fortune Telling (Spanish)
  (fort_id, 'es', 'Predicción del Futuro',
   'Predecir resultados negativos sin evidencia',
   'La predicción del futuro es asumir que sabes cómo resultarán las cosas, usualmente negativamente.',
   ARRAY['El futuro es incierto - ¿qué evidencia tienes?', '¿Has estado equivocado sobre predicciones antes?'],
   ARRAY['¿Qué evidencia tengo de este resultado?', '¿Cuántas veces he estado equivocado antes?', '¿Qué más podría pasar?']),

  -- Labeling (Spanish)
  (lab_id, 'es', 'Etiquetado',
   'Asignar etiquetas negativas a ti mismo o a otros',
   'El etiquetado es poner una etiqueta global negativa en ti mismo o en otros basado en un solo evento.',
   ARRAY['Un error no te define', '¿Describirías así a un amigo?'],
   ARRAY['¿Es esta etiqueta precisa o solo un error?', '¿Qué evidencia contradice esta etiqueta?', '¿Cómo describirías esto a un amigo?']),

  -- Should Statements (Spanish)
  (sho_id, 'es', 'Declaraciones de "Debería"',
   'Tener expectativas rígidas sobre cómo deberían ser las cosas',
   'Las declaraciones de debería son reglas rígidas sobre cómo deben ser tú, otros o el mundo.',
   ARRAY['Reemplaza "debería" con "podría" o "preferiría"', '¿De dónde viene esta regla?'],
   ARRAY['¿Esta regla es realista?', '¿Qué pasaría si la flexibilizara?', '¿Es esto una preferencia o un requisito?']),

  -- Emotional Reasoning (Spanish)
  (emf_id, 'es', 'Razonamiento Emocional',
   'Creer que algo es verdad porque se siente verdad',
   'El razonamiento emocional es asumir que tus sentimientos reflejan la realidad objetiva.',
   ARRAY['Los sentimientos son válidos, pero no siempre reflejan hechos', '¿Qué dirían los hechos?'],
   ARRAY['¿Cómo describiría esto un observador neutral?', '¿Qué evidencia hay más allá de mi sentimiento?', '¿He sentido esto antes y estado equivocado?']),

  -- Disqualifying the Positive (Spanish)
  (mins_id, 'es', 'Descalificar lo Positivo',
   'Rechazar experiencias positivas',
   'Descalificar lo positivo es negar o minimizar las cosas buenas que suceden.',
   ARRAY['Las cosas positivas también cuentan', '¿Por qué es difícil aceptar el elogio?'],
   ARRAY['¿Qué evidencia tengo de que no cuenta?', '¿Aceptaría esto como logro en otra persona?', '¿Por qué me resisto a reconocer esto?']),

  -- Personalization and Blame (Spanish)
  (blame_id, 'es', 'Personalización y Culpa',
   'Asumir responsabilidad excesiva o culpar a otros injustamente',
   'La personalización es asumir que todo es tu culpa o culpar a otros cuando hay múltiples factores.',
   ARRAY['¿Qué otros factores contribuyeron?', 'La situación es más compleja que la culpa de una persona'],
   ARRAY['¿Qué porcentaje es realmente mi responsabilidad?', '¿Qué otros factores jugaron un papel?', '¿Estoy asumiendo control sobre cosas que no controlo?']),

  -- Comparison (Spanish)
  (comp_id, 'es', 'Comparación',
   'Medirse constantemente contra otros',
   'La comparación es evaluar tu valía basándote en cómo te comparas con otros.',
   ARRAY['Tu camino es único - la comparación es injusta', '¿Qué son tus propias fortalezas?'],
   ARRAY['¿Estoy comparando mi interior con el exterior de alguien más?', '¿Qué gano con esta comparación?', '¿Cuáles son mis propias fortalezas únicas?']),

  -- Regret Orientation (Spanish)
  (rg_id, 'es', 'Orientación al Arrepentimiento',
   'Enfocarse en decisiones pasadas y "si solo"',
   'La orientación al arrepentimiento es quedar atrapado en decisiones pasadas en lugar de aprender y seguir adelante.',
   ARRAY['El pasado no puede cambiarse - ¿qué puedes aprender?', '¿Qué harías diferente con lo que sabes ahora?'],
   ARRAY['¿Qué aprendí de esta experiencia?', '¿Tomé la mejor decisión con la información que tenía?', '¿Cómo puedo usar esto para avanzar?']),

  -- What-If Thinking (Spanish)
  (what_id, 'es', 'Pensamiento "Qué Pasaría Si"',
   'Preocuparse por futuros posibles negativos',
   'El pensamiento qué pasaría si es quedarse atrapado en escenarios futuros posibles, usualmente negativos.',
   ARRAY['Enfócate en lo que puedes controlar ahora', '¿Cuál es la probabilidad real de esto?'],
   ARRAY['¿Qué tan probable es esto realmente?', '¿Qué puedo controlar en este momento?', '¿Me ha ayudado preocuparme antes?']);

  -- Portuguese (pt-BR) translations
  INSERT INTO distortion_education (distortion_id, locale, name_translated, short_description_translated, full_description_translated, reframe_templates_translated, questions_translated) VALUES
  
  -- All-or-Nothing Thinking (Portuguese)
  (aon_id, 'pt-BR', 'Pensamento Tudo ou Nada',
   'Ver as coisas em categorias pretas ou brancas',
   'O pensamento tudo ou nada significa ver situações em apenas duas categorias em vez de em um continuum.',
   ARRAY['A perfeição não é possível. O que deu certo?', 'Existem tons de cinza nesta situação?'],
   ARRAY['Que evidência tenho que apoia ambos os lados?', 'Estou vendo isso em extremos?', 'Qual é o meio-termo aqui?']),

  -- Catastrophizing (Portuguese)
  (cat_id, 'pt-BR', 'Catastrofização',
   'Esperar o pior resultado possível',
   'Catastrofizar é amplificar o negativo e minimizar o positivo, assumindo que as coisas darão errado.',
   ARRAY['O que é mais provável de acontecer?', 'Como você lidou com desafios antes?'],
   ARRAY['Qual é a evidência real do pior cenário?', 'Que outros resultados são possíveis?', 'Já sobrevivi a situações semelhantes antes?']),

  -- Mind Reading (Portuguese)
  (mind_id, 'pt-BR', 'Leitura de Mentes',
   'Assumir que você sabe o que os outros pensam',
   'Leitura de mentes é assumir que você sabe o que os outros estão pensando sem evidência real.',
   ARRAY['Você não pode saber o que pensam sem perguntar', 'Você poderia estar projetando seus próprios medos?'],
   ARRAY['Que evidência concreta tenho do que eles pensam?', 'Perguntei diretamente?', 'Poderia haver outras explicações?']),

  -- Fortune Telling (Portuguese)
  (fort_id, 'pt-BR', 'Previsão do Futuro',
   'Prever resultados negativos sem evidência',
   'Previsão do futuro é assumir que você sabe como as coisas vão resultar, geralmente negativamente.',
   ARRAY['O futuro é incerto - que evidência você tem?', 'Você já esteve errado sobre previsões antes?'],
   ARRAY['Que evidência tenho deste resultado?', 'Quantas vezes estive errado antes?', 'O que mais poderia acontecer?']),

  -- Labeling (Portuguese)
  (lab_id, 'pt-BR', 'Rotulação',
   'Atribuir rótulos negativos a si mesmo ou aos outros',
   'Rotular é colocar um rótulo global negativo em si mesmo ou nos outros com base em um único evento.',
   ARRAY['Um erro não te define', 'Você descreveria um amigo assim?'],
   ARRAY['Este rótulo é preciso ou apenas um erro?', 'Que evidência contradiz este rótulo?', 'Como eu descreveria isso para um amigo?']),

  -- Should Statements (Portuguese)
  (sho_id, 'pt-BR', 'Declarações de "Deveria"',
   'Ter expectativas rígidas sobre como as coisas deveriam ser',
   'Declarações de deveria são regras rígidas sobre como você, os outros ou o mundo devem ser.',
   ARRAY['Substitua "deveria" por "poderia" ou "preferiria"', 'De onde vem esta regra?'],
   ARRAY['Esta regra é realista?', 'O que aconteceria se eu a flexibilizasse?', 'Isso é uma preferência ou um requisito?']),

  -- Emotional Reasoning (Portuguese)
  (emf_id, 'pt-BR', 'Raciocínio Emocional',
   'Acreditar que algo é verdade porque parece verdade',
   'Raciocínio emocional é assumir que seus sentimentos refletem a realidade objetiva.',
   ARRAY['Sentimentos são válidos, mas nem sempre refletem fatos', 'O que os fatos diriam?'],
   ARRAY['Como um observador neutro descreveria isso?', 'Que evidência existe além do meu sentimento?', 'Já senti isso antes e estava errado?']),

  -- Disqualifying the Positive (Portuguese)
  (mins_id, 'pt-BR', 'Desqualificar o Positivo',
   'Rejeitar experiências positivas',
   'Desqualificar o positivo é negar ou minimizar as coisas boas que acontecem.',
   ARRAY['Coisas positivas também contam', 'Por que é difícil aceitar elogios?'],
   ARRAY['Que evidência tenho de que não conta?', 'Aceitaria isso como conquista em outra pessoa?', 'Por que resisto em reconhecer isso?']),

  -- Personalization and Blame (Portuguese)
  (blame_id, 'pt-BR', 'Personalização e Culpa',
   'Assumir responsabilidade excessiva ou culpar outros injustamente',
   'Personalização é assumir que tudo é sua culpa ou culpar outros quando há múltiplos fatores.',
   ARRAY['Que outros fatores contribuíram?', 'A situação é mais complexa que a culpa de uma pessoa'],
   ARRAY['Qual porcentagem é realmente minha responsabilidade?', 'Que outros fatores tiveram papel?', 'Estou assumindo controle sobre coisas que não controlo?']),

  -- Comparison (Portuguese)
  (comp_id, 'pt-BR', 'Comparação',
   'Medir-se constantemente contra outros',
   'Comparação é avaliar seu valor baseado em como você se compara com outros.',
   ARRAY['Seu caminho é único - comparação é injusta', 'Quais são suas próprias forças?'],
   ARRAY['Estou comparando meu interior com o exterior de outra pessoa?', 'O que ganho com esta comparação?', 'Quais são minhas próprias forças únicas?']),

  -- Regret Orientation (Portuguese)
  (rg_id, 'pt-BR', 'Orientação ao Arrependimento',
   'Focar em decisões passadas e "se apenas"',
   'Orientação ao arrependimento é ficar preso em decisões passadas em vez de aprender e seguir em frente.',
   ARRAY['O passado não pode ser mudado - o que você pode aprender?', 'O que faria diferente com o que sabe agora?'],
   ARRAY['O que aprendi com esta experiência?', 'Tomei a melhor decisão com a informação que tinha?', 'Como posso usar isso para avançar?']),

  -- What-If Thinking (Portuguese)
  (what_id, 'pt-BR', 'Pensamento "E Se"',
   'Preocupar-se com futuros possíveis negativos',
   'Pensamento e se é ficar preso em cenários futuros possíveis, geralmente negativos.',
   ARRAY['Foque no que você pode controlar agora', 'Qual é a probabilidade real disso?'],
   ARRAY['Quão provável isso realmente é?', 'O que posso controlar neste momento?', 'Preocupar-me ajudou antes?']);

      RAISE NOTICE 'Added 22 cognitive distortion translations (Spanish and Portuguese)';
    END; -- End nested DECLARE block
  ELSE
    RAISE NOTICE 'cognitive_distortions or distortion_education table does not exist yet, skipping translations';
  END IF;
END $$;
