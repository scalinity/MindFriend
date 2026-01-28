#!/usr/bin/env python3
"""
Translate remaining missing strings in Localizable.xcstrings - Batch 2
"""
import json

# Additional translations
TRANSLATIONS = {
    # A
    "Adaptation Behavior": {"es": "Comportamiento de adaptación", "pt-BR": "Comportamento de adaptação"},
    "Adaptation Mode": {"es": "Modo de adaptación", "pt-BR": "Modo de adaptação"},
    "Add %@ to the list": {"es": "Agregar %@ a la lista", "pt-BR": "Adicionar %@ à lista"},
    "Add Feedback (Optional)": {"es": "Agregar comentarios (opcional)", "pt-BR": "Adicionar feedback (opcional)"},
    "Add Goal": {"es": "Agregar meta", "pt-BR": "Adicionar meta"},
    "Add Your First Event": {"es": "Agrega tu primer evento", "pt-BR": "Adicione seu primeiro evento"},
    "Add context to help others understand when this strategy works best.": {"es": "Agrega contexto para ayudar a otros a entender cuándo funciona mejor esta estrategia.", "pt-BR": "Adicione contexto para ajudar outros a entender quando esta estratégia funciona melhor."},
    "Additional Notes (Optional)": {"es": "Notas adicionales (opcional)", "pt-BR": "Notas adicionais (opcional)"},
    "Additional details (optional)": {"es": "Detalles adicionales (opcional)", "pt-BR": "Detalhes adicionais (opcional)"},
    "Adjust Difficulty": {"es": "Ajustar dificultad", "pt-BR": "Ajustar dificuldade"},
    "Adjust the strength of vibrations for tactile patterns. Lower values are gentler.": {"es": "Ajusta la intensidad de las vibraciones para patrones táctiles. Valores más bajos son más suaves.", "pt-BR": "Ajuste a intensidade das vibrações para padrões táteis. Valores mais baixos são mais suaves."},
    "Advance to Next Phase": {"es": "Avanzar a la siguiente fase", "pt-BR": "Avançar para a próxima fase"},
    "Advance to next phase": {"es": "Avanzar a la siguiente fase", "pt-BR": "Avançar para a próxima fase"},
    "After 2 weeks of intervention history, MindFriend will learn your optimal timing patterns.": {"es": "Después de 2 semanas de historial de intervenciones, MindFriend aprenderá tus patrones de tiempo óptimos.", "pt-BR": "Após 2 semanas de histórico de intervenções, MindFriend aprenderá seus padrões de tempo ideais."},
    "Agent Active": {"es": "Agente activo", "pt-BR": "Agente ativo"},
    "Agent Paused": {"es": "Agente pausado", "pt-BR": "Agente pausado"},
    "Alert when score drops below: %lld": {"es": "Alertar cuando la puntuación baje de: %lld", "pt-BR": "Alertar quando a pontuação cair abaixo de: %lld"},
    "Ambient background with %@ theme": {"es": "Fondo ambiental con tema %@", "pt-BR": "Fundo ambiente com tema %@"},
    "Analyze your mood history to calculate your wellbeing debt score.": {"es": "Analiza tu historial de ánimo para calcular tu puntuación de deuda de bienestar.", "pt-BR": "Analise seu histórico de humor para calcular sua pontuação de dívida de bem-estar."},
    "Analyzing your patterns and selecting optimal actions": {"es": "Analizando tus patrones y seleccionando acciones óptimas", "pt-BR": "Analisando seus padrões e selecionando ações ideais"},
    "Animations automatically respect your device's Reduce Motion setting": {"es": "Las animaciones respetan automáticamente la configuración de Reducir movimiento de tu dispositivo", "pt-BR": "As animações respeitam automaticamente a configuração Reduzir Movimento do seu dispositivo"},
    "Anonymous Contribution": {"es": "Contribución anónima", "pt-BR": "Contribuição anônima"},
    "Any factors that affected your sleep?": {"es": "¿Algún factor que afectó tu sueño?", "pt-BR": "Algum fator que afetou seu sono?"},
    "Any other feedback? (optional)": {"es": "¿Algún otro comentario? (opcional)", "pt-BR": "Algum outro feedback? (opcional)"},
    "Anything memorable from your dreams?": {"es": "¿Algo memorable de tus sueños?", "pt-BR": "Algo memorável dos seus sonhos?"},
    "Apple Watch": {"es": "Apple Watch", "pt-BR": "Apple Watch"},
    "Approaching Threshold": {"es": "Acercándose al umbral", "pt-BR": "Aproximando-se do limite"},
    "Are you sure you want to end this mentorship relationship?": {"es": "¿Estás seguro de que quieres terminar esta relación de mentoría?", "pt-BR": "Tem certeza de que deseja encerrar este relacionamento de mentoria?"},
    "Armor Lead Time": {"es": "Tiempo de preparación de armadura", "pt-BR": "Tempo de preparação de armadura"},
    "As the community grows, personalized insights will appear here.": {"es": "A medida que la comunidad crece, aparecerán perspectivas personalizadas aquí.", "pt-BR": "À medida que a comunidade cresce, insights personalizados aparecerão aqui."},
    "Audio will fade out gently over the last 30 seconds": {"es": "El audio se desvanecerá suavemente durante los últimos 30 segundos", "pt-BR": "O áudio diminuirá suavemente durante os últimos 30 segundos"},
    "Authorized": {"es": "Autorizado", "pt-BR": "Autorizado"},
    "Auto-Adjust by Time": {"es": "Ajuste automático por tiempo", "pt-BR": "Ajuste automático por tempo"},
    "Auto-pause will pause your session when interrupted by phone calls or notifications. The default duration is used when starting a new session.": {"es": "La pausa automática pausará tu sesión cuando sea interrumpida por llamadas o notificaciones. La duración predeterminada se usa al iniciar una nueva sesión.", "pt-BR": "A pausa automática pausará sua sessão quando interrompida por chamadas ou notificações. A duração padrão é usada ao iniciar uma nova sessão."},
    "Auto-sync HealthKit": {"es": "Sincronización automática de HealthKit", "pt-BR": "Sincronização automática do HealthKit"},
    "Automatic Calculation": {"es": "Cálculo automático", "pt-BR": "Cálculo automático"},
    "Automatically switch between dawn, day, dusk, and night themes": {"es": "Cambiar automáticamente entre temas de amanecer, día, atardecer y noche", "pt-BR": "Alternar automaticamente entre temas de amanhecer, dia, entardecer e noite"},
    "Avoid Blue Light": {"es": "Evitar luz azul", "pt-BR": "Evitar luz azul"},
    
    # B
    "BPM": {"es": "PPM", "pt-BR": "BPM"},
    "Background Style": {"es": "Estilo de fondo", "pt-BR": "Estilo de fundo"},
    "Background sound files not yet installed": {"es": "Archivos de sonido de fondo aún no instalados", "pt-BR": "Arquivos de som de fundo ainda não instalados"},
    "Balanced (default)": {"es": "Equilibrado (predeterminado)", "pt-BR": "Equilibrado (padrão)"},
    "Based on %lld alerts with feedback": {"es": "Basado en %lld alertas con comentarios", "pt-BR": "Baseado em %lld alertas com feedback"},
    "Based on %lld data points": {"es": "Basado en %lld puntos de datos", "pt-BR": "Baseado em %lld pontos de dados"},
    "Based on voice analysis using on-device AI emotion detection. Your voice data is never stored or shared.": {"es": "Basado en análisis de voz usando detección de emociones con IA en el dispositivo. Tus datos de voz nunca se almacenan ni comparten.", "pt-BR": "Baseado em análise de voz usando detecção de emoções com IA no dispositivo. Seus dados de voz nunca são armazenados ou compartilhados."},
    "Based on your completion and rating patterns, interventions are more likely during your best times.": {"es": "Basado en tus patrones de finalización y calificación, las intervenciones son más probables durante tus mejores momentos.", "pt-BR": "Com base em seus padrões de conclusão e avaliação, as intervenções são mais prováveis durante seus melhores momentos."},
    "Be the first to share a %@ strategy!": {"es": "¡Sé el primero en compartir una estrategia de %@!", "pt-BR": "Seja o primeiro a compartilhar uma estratégia de %@!"},
    "Bedtime Reminder": {"es": "Recordatorio de hora de dormir", "pt-BR": "Lembrete de hora de dormir"},
    "Begin Journey": {"es": "Comenzar viaje", "pt-BR": "Iniciar jornada"},
    "Begin a new transition journey": {"es": "Comenzar un nuevo viaje de transición", "pt-BR": "Iniciar uma nova jornada de transição"},
    "Begins the suggested wellness exercise": {"es": "Comienza el ejercicio de bienestar sugerido", "pt-BR": "Inicia o exercício de bem-estar sugerido"},
    "Best": {"es": "Mejor", "pt-BR": "Melhor"},
    "Best Match": {"es": "Mejor coincidencia", "pt-BR": "Melhor combinação"},
    "Biofeedback": {"es": "Biofeedback", "pt-BR": "Biofeedback"},
    "Breakthrough!": {"es": "¡Avance!", "pt-BR": "Avanço!"},
    "Building your signature": {"es": "Construyendo tu firma", "pt-BR": "Construindo sua assinatura"},
    
    # C
    "Calculate Now": {"es": "Calcular ahora", "pt-BR": "Calcular agora"},
    "Calculating...": {"es": "Calculando...", "pt-BR": "Calculando..."},
    "Calculation Error": {"es": "Error de cálculo", "pt-BR": "Erro de cálculo"},
    "Calendar": {"es": "Calendario", "pt-BR": "Calendário"},
    "Calendar Access": {"es": "Acceso al calendario", "pt-BR": "Acesso ao calendário"},
    "Calendar Event Armor": {"es": "Armadura de eventos del calendario", "pt-BR": "Armadura de eventos do calendário"},
    "Calendar Triggers": {"es": "Disparadores del calendario", "pt-BR": "Gatilhos do calendário"},
    "Calm your nervous system": {"es": "Calma tu sistema nervioso", "pt-BR": "Acalme seu sistema nervoso"},
    "Capacity": {"es": "Capacidad", "pt-BR": "Capacidade"},
    "Capacity Breakdown": {"es": "Desglose de capacidad", "pt-BR": "Detalhamento de capacidade"},
    "Category filter": {"es": "Filtro de categoría", "pt-BR": "Filtro de categoria"},
    "Challenging factor": {"es": "Factor desafiante", "pt-BR": "Fator desafiador"},
    "Change: %@ from baseline": {"es": "Cambio: %@ desde la línea base", "pt-BR": "Mudança: %@ da linha de base"},
    "Character count": {"es": "Conteo de caracteres", "pt-BR": "Contagem de caracteres"},
    "Choose how your weekly stories are written. This will apply to future stories.": {"es": "Elige cómo se escriben tus historias semanales. Esto se aplicará a historias futuras.", "pt-BR": "Escolha como suas histórias semanais são escritas. Isso se aplicará a histórias futuras."},
    "Choose the emotion or situation this strategy helps with.": {"es": "Elige la emoción o situación con la que esta estrategia ayuda.", "pt-BR": "Escolha a emoção ou situação com a qual esta estratégia ajuda."},
    "Clear Override": {"es": "Limpiar anulación", "pt-BR": "Limpar substituição"},
    "Close and provide feedback": {"es": "Cerrar y proporcionar comentarios", "pt-BR": "Fechar e fornecer feedback"},
    "Close prompt": {"es": "Cerrar indicación", "pt-BR": "Fechar prompt"},
    "Coach feedback acknowledged": {"es": "Comentarios del coach reconocidos", "pt-BR": "Feedback do coach reconhecido"},
    "Coaching Status": {"es": "Estado del coaching", "pt-BR": "Status do coaching"},
    "Common examples": {"es": "Ejemplos comunes", "pt-BR": "Exemplos comuns"},
    "Company Name": {"es": "Nombre de la empresa", "pt-BR": "Nome da empresa"},
    "Company error: %@": {"es": "Error de empresa: %@", "pt-BR": "Erro da empresa: %@"},
    "Compatibility": {"es": "Compatibilidad", "pt-BR": "Compatibilidade"},
    "Compatibility Score": {"es": "Puntuación de compatibilidad", "pt-BR": "Pontuação de compatibilidade"},
    "Compatibility: %lld%%": {"es": "Compatibilidad: %lld%%", "pt-BR": "Compatibilidade: %lld%%"},
    "Complete Check-In": {"es": "Completar registro", "pt-BR": "Completar check-in"},
    "Complete Discovery": {"es": "Completar descubrimiento", "pt-BR": "Completar descoberta"},
    "Complete Exercise": {"es": "Completar ejercicio", "pt-BR": "Completar exercício"},
    "Complete Now": {"es": "Completar ahora", "pt-BR": "Completar agora"},
    "Complete a biofeedback exercise to see your history here.": {"es": "Completa un ejercicio de biofeedback para ver tu historial aquí.", "pt-BR": "Complete um exercício de biofeedback para ver seu histórico aqui."},
    "Complete exercise": {"es": "Completar ejercicio", "pt-BR": "Completar exercício"},
    "Complete mood check-ins and exercises to see your insights": {"es": "Completa registros de ánimo y ejercicios para ver tus perspectivas", "pt-BR": "Complete check-ins de humor e exercícios para ver seus insights"},
    "Complete yesterday's quest before time runs out": {"es": "Completa la misión de ayer antes de que se acabe el tiempo", "pt-BR": "Complete a missão de ontem antes que o tempo acabe"},
    "Complete your daily check-in to calculate your capacity": {"es": "Completa tu registro diario para calcular tu capacidad", "pt-BR": "Complete seu check-in diário para calcular sua capacidade"},
    "Components": {"es": "Componentes", "pt-BR": "Componentes"},
    "Configure": {"es": "Configurar", "pt-BR": "Configurar"},
    "Confirm your top 5 values": {"es": "Confirma tus 5 valores principales", "pt-BR": "Confirme seus 5 principais valores"},
    "Congratulations!": {"es": "¡Felicitaciones!", "pt-BR": "Parabéns!"},
    "Connect HealthKit": {"es": "Conectar HealthKit", "pt-BR": "Conectar HealthKit"},
    "Connect HealthKit or manually log your sleep to get personalized insights": {"es": "Conecta HealthKit o registra manualmente tu sueño para obtener perspectivas personalizadas", "pt-BR": "Conecte o HealthKit ou registre manualmente seu sono para obter insights personalizados"},
    "Context (Optional)": {"es": "Contexto (opcional)", "pt-BR": "Contexto (opcional)"},
    "Continue journaling without exploring this pattern": {"es": "Continuar escribiendo sin explorar este patrón", "pt-BR": "Continuar escrevendo sem explorar este padrão"},
    "Continue to next step": {"es": "Continuar al siguiente paso", "pt-BR": "Continuar para o próximo passo"},
    "Continue to: %@": {"es": "Continuar a: %@", "pt-BR": "Continuar para: %@"},
    "Contribute": {"es": "Contribuir", "pt-BR": "Contribuir"},
    "Contribute Anonymous Data": {"es": "Contribuir datos anónimos", "pt-BR": "Contribuir dados anônimos"},
    "Contributing Factors": {"es": "Factores contribuyentes", "pt-BR": "Fatores contribuintes"},
    "Control how detailed your weekly stories are.": {"es": "Controla qué tan detalladas son tus historias semanales.", "pt-BR": "Controle o quão detalhadas são suas histórias semanais."},
    "Conversation Rehearsal Studio": {"es": "Estudio de ensayo de conversaciones", "pt-BR": "Estúdio de ensaio de conversas"},
    "Cool Temperature": {"es": "Temperatura fresca", "pt-BR": "Temperatura fresca"},
    "Copied": {"es": "Copiado", "pt-BR": "Copiado"},
    "Copy": {"es": "Copiar", "pt-BR": "Copiar"},
    "Count": {"es": "Conteo", "pt-BR": "Contagem"},
    "Create My Signature": {"es": "Crear mi firma", "pt-BR": "Criar minha assinatura"},
    "Create a personalized exercise just for you": {"es": "Crea un ejercicio personalizado solo para ti", "pt-BR": "Crie um exercício personalizado só para você"},
    "Creating your artwork...": {"es": "Creando tu obra de arte...", "pt-BR": "Criando sua arte..."},
    "Creating your routine...": {"es": "Creando tu rutina...", "pt-BR": "Criando sua rotina..."},
    "Crop Photo": {"es": "Recortar foto", "pt-BR": "Recortar foto"},
    "Current Capacity": {"es": "Capacidad actual", "pt-BR": "Capacidade atual"},
    "Currently Active (%lld)": {"es": "Actualmente activo (%lld)", "pt-BR": "Atualmente ativo (%lld)"},
    "Currently selected. Tap to deselect": {"es": "Actualmente seleccionado. Toca para deseleccionar", "pt-BR": "Atualmente selecionado. Toque para desmarcar"},
    "Customize ambient backgrounds that adapt to your mood and time of day.": {"es": "Personaliza fondos ambientales que se adaptan a tu estado de ánimo y hora del día.", "pt-BR": "Personalize fundos ambientes que se adaptam ao seu humor e hora do dia."},
    "Cycle %lld/%lld": {"es": "Ciclo %lld/%lld", "pt-BR": "Ciclo %lld/%lld"},
    
    # D
    "Daily Check-In": {"es": "Registro diario", "pt-BR": "Check-in diário"},
    "Daily Limit": {"es": "Límite diario", "pt-BR": "Limite diário"},
    "Daily Target": {"es": "Meta diaria", "pt-BR": "Meta diária"},
    "Dark Room": {"es": "Habitación oscura", "pt-BR": "Quarto escuro"},
    "Data Display": {"es": "Visualización de datos", "pt-BR": "Exibição de dados"},
    "Data Sync": {"es": "Sincronización de datos", "pt-BR": "Sincronização de dados"},
    "Data will appear as you progress through the exercise": {"es": "Los datos aparecerán a medida que avances en el ejercicio", "pt-BR": "Os dados aparecerão conforme você avança no exercício"},
    "Date Range": {"es": "Rango de fechas", "pt-BR": "Intervalo de datas"},
    "Day %lld • %@": {"es": "Día %lld • %@", "pt-BR": "Dia %lld • %@"},
    "Decline Request": {"es": "Rechazar solicitud", "pt-BR": "Recusar solicitação"},
    "Delete this life event?": {"es": "¿Eliminar este evento de vida?", "pt-BR": "Excluir este evento de vida?"},
    "Delivered: %@": {"es": "Entregado: %@", "pt-BR": "Entregue: %@"},
    "Denied": {"es": "Denegado", "pt-BR": "Negado"},
    "Deposits (%lld)": {"es": "Depósitos (%lld)", "pt-BR": "Depósitos (%lld)"},
    "Deselect All": {"es": "Deseleccionar todo", "pt-BR": "Desmarcar tudo"},
    "Detect emotions from your voice using on-device AI": {"es": "Detecta emociones de tu voz usando IA en el dispositivo", "pt-BR": "Detecte emoções da sua voz usando IA no dispositivo"},
    "Detected %@": {"es": "Detectado %@", "pt-BR": "Detectado %@"},
    "Detected at %@": {"es": "Detectado a las %@", "pt-BR": "Detectado às %@"},
    "Detection Sensitivity": {"es": "Sensibilidad de detección", "pt-BR": "Sensibilidade de detecção"},
    "Device Capabilities": {"es": "Capacidades del dispositivo", "pt-BR": "Capacidades do dispositivo"},
    "Difficulty Settings": {"es": "Configuración de dificultad", "pt-BR": "Configurações de dificuldade"},
    "Dim": {"es": "Tenue", "pt-BR": "Fraco"},
    "Disabled": {"es": "Deshabilitado", "pt-BR": "Desativado"},
    "Discover Your Values": {"es": "Descubre tus valores", "pt-BR": "Descubra seus valores"},
    "Dismiss Alert": {"es": "Descartar alerta", "pt-BR": "Dispensar alerta"},
    "Dismisses this suggestion and suppresses coaching for 30 minutes": {"es": "Descarta esta sugerencia y suprime el coaching por 30 minutos", "pt-BR": "Dispensa esta sugestão e suprime o coaching por 30 minutos"},
    "Distortions to Ignore": {"es": "Distorsiones a ignorar", "pt-BR": "Distorções a ignorar"},
    
    # E
    "Edit Warning Signs": {"es": "Editar señales de alerta", "pt-BR": "Editar sinais de alerta"},
    "Effectiveness": {"es": "Efectividad", "pt-BR": "Eficácia"},
    "Efficacy Insights": {"es": "Perspectivas de eficacia", "pt-BR": "Insights de eficácia"},
    "Email error: %@": {"es": "Error de email: %@", "pt-BR": "Erro de email: %@"},
    "Emotion Analysis": {"es": "Análisis de emociones", "pt-BR": "Análise de emoções"},
    "Emotion Breakdown": {"es": "Desglose de emociones", "pt-BR": "Detalhamento de emoções"},
    "Emotion Detection": {"es": "Detección de emociones", "pt-BR": "Detecção de emoções"},
    "Emotion Settings": {"es": "Configuración de emociones", "pt-BR": "Configurações de emoções"},
    "Emotion analysis runs entirely on your device using CoreML. No voice data is sent to any server for emotion detection.": {"es": "El análisis de emociones se ejecuta completamente en tu dispositivo usando CoreML. No se envían datos de voz a ningún servidor para la detección de emociones.", "pt-BR": "A análise de emoções é executada inteiramente no seu dispositivo usando CoreML. Nenhum dado de voz é enviado a qualquer servidor para detecção de emoções."},
    "Emotional Trajectory": {"es": "Trayectoria emocional", "pt-BR": "Trajetória emocional"},
    "Empty": {"es": "Vacío", "pt-BR": "Vazio"},
    "Enable Biofeedback": {"es": "Habilitar biofeedback", "pt-BR": "Ativar biofeedback"},
    "Enable Daily Briefing": {"es": "Habilitar resumen diario", "pt-BR": "Ativar resumo diário"},
    "Enable Proactive Check-ins": {"es": "Habilitar registros proactivos", "pt-BR": "Ativar check-ins proativos"},
    "Enable Smart Interventions": {"es": "Habilitar intervenciones inteligentes", "pt-BR": "Ativar intervenções inteligentes"},
    "Enable Thinking Coach": {"es": "Habilitar coach de pensamiento", "pt-BR": "Ativar coach de pensamento"},
    "Enable alerts": {"es": "Habilitar alertas", "pt-BR": "Ativar alertas"},
    "Enable recommendations in Settings to see community wisdom.": {"es": "Habilita las recomendaciones en Configuración para ver la sabiduría de la comunidad.", "pt-BR": "Ative as recomendações nas Configurações para ver a sabedoria da comunidade."},
    "Enable to see your weekly pattern summary": {"es": "Habilita para ver tu resumen de patrones semanales", "pt-BR": "Ative para ver seu resumo de padrões semanais"},
    "Enabled": {"es": "Habilitado", "pt-BR": "Ativado"},
    "End Date": {"es": "Fecha de finalización", "pt-BR": "Data de término"},
    "End time": {"es": "Hora de finalización", "pt-BR": "Hora de término"},
    "Energy: %lld/10": {"es": "Energía: %lld/10", "pt-BR": "Energia: %lld/10"},
    "Enter a description of the profile picture you want to generate, between 3 and 200 characters": {"es": "Ingresa una descripción de la foto de perfil que deseas generar, entre 3 y 200 caracteres", "pt-BR": "Digite uma descrição da foto de perfil que deseja gerar, entre 3 e 200 caracteres"},
    "Enter an item first": {"es": "Ingresa un elemento primero", "pt-BR": "Digite um item primeiro"},
    "Enter at least 3 characters first": {"es": "Ingresa al menos 3 caracteres primero", "pt-BR": "Digite pelo menos 3 caracteres primeiro"},
    "Enter score 0-%lld": {"es": "Ingresa puntuación 0-%lld", "pt-BR": "Digite pontuação 0-%lld"},
    "Error Loading Transactions": {"es": "Error al cargar transacciones", "pt-BR": "Erro ao carregar transações"},
    "Estimated %lldh until crisis": {"es": "Estimado %lldh hasta la crisis", "pt-BR": "Estimado %lldh até a crise"},
    "Event Type": {"es": "Tipo de evento", "pt-BR": "Tipo de evento"},
    "Everyone has unique patterns that appear before stress overwhelms them. By learning your personal warning signs, MindFriend can alert you 24-72 hours before a crisis and help you intervene early.": {"es": "Todos tienen patrones únicos que aparecen antes de que el estrés los abrume. Al aprender tus señales de alerta personales, MindFriend puede alertarte 24-72 horas antes de una crisis y ayudarte a intervenir temprano.", "pt-BR": "Todos têm padrões únicos que aparecem antes do estresse sobrecarregá-los. Ao aprender seus sinais de alerta pessoais, MindFriend pode alertá-lo 24-72 horas antes de uma crise e ajudá-lo a intervir cedo."},
    "Excellent": {"es": "Excelente", "pt-BR": "Excelente"},
    "Exercise Effectiveness": {"es": "Efectividad del ejercicio", "pt-BR": "Eficácia do exercício"},
    "Expertise": {"es": "Experiencia", "pt-BR": "Especialização"},
    "Expires": {"es": "Expira", "pt-BR": "Expira"},
    "Explain Reasoning": {"es": "Explicar razonamiento", "pt-BR": "Explicar raciocínio"},
    "Explanation: %@": {"es": "Explicación: %@", "pt-BR": "Explicação: %@"},
    "Explore This": {"es": "Explorar esto", "pt-BR": "Explorar isso"},
    "Explore this pattern": {"es": "Explorar este patrón", "pt-BR": "Explorar este padrão"},
    "Export Compass": {"es": "Exportar brújula", "pt-BR": "Exportar bússola"},
    "Export Health Data (FHIR)": {"es": "Exportar datos de salud (FHIR)", "pt-BR": "Exportar dados de saúde (FHIR)"},
    "Extend Session?": {"es": "¿Extender sesión?", "pt-BR": "Estender sessão?"},
    "Extended": {"es": "Extendido", "pt-BR": "Estendido"},
    
    # F
    "Failed to Load Insights": {"es": "Error al cargar perspectivas", "pt-BR": "Falha ao carregar insights"},
    "Favorites (%lld)": {"es": "Favoritos (%lld)", "pt-BR": "Favoritos (%lld)"},
    "Favorites Only": {"es": "Solo favoritos", "pt-BR": "Apenas favoritos"},
    "Feedback Received": {"es": "Comentarios recibidos", "pt-BR": "Feedback recebido"},
    "Fewer Alerts": {"es": "Menos alertas", "pt-BR": "Menos alertas"},
    "Find a mentor or become one to start meaningful connections.": {"es": "Encuentra un mentor o conviértete en uno para comenzar conexiones significativas.", "pt-BR": "Encontre um mentor ou torne-se um para iniciar conexões significativas."},
    "Finding mentors...": {"es": "Buscando mentores...", "pt-BR": "Encontrando mentores..."},
    "Finish": {"es": "Finalizar", "pt-BR": "Finalizar"},
    "Finish the grounding exercise": {"es": "Terminar el ejercicio de conexión a tierra", "pt-BR": "Finalizar o exercício de aterramento"},
    "First dose": {"es": "Primera dosis", "pt-BR": "Primeira dose"},
    "Focus: %@": {"es": "Enfoque: %@", "pt-BR": "Foco: %@"},
    "Follow the guided breathing pattern": {"es": "Sigue el patrón de respiración guiado", "pt-BR": "Siga o padrão de respiração guiado"},
    "Follow these daily actions to replenish your wellbeing reserves and avoid crashes.": {"es": "Sigue estas acciones diarias para reponer tus reservas de bienestar y evitar colapsos.", "pt-BR": "Siga estas ações diárias para repor suas reservas de bem-estar e evitar colapsos."},
    "For you": {"es": "Para ti", "pt-BR": "Para você"},
    "Free tier: 1 vacation per month": {"es": "Nivel gratuito: 1 vacación por mes", "pt-BR": "Nível gratuito: 1 férias por mês"},
    "Frequent (more suggestions)": {"es": "Frecuente (más sugerencias)", "pt-BR": "Frequente (mais sugestões)"},
    "From:": {"es": "De:", "pt-BR": "De:"},
    
    # G
    "Generate AI profile picture": {"es": "Generar foto de perfil con IA", "pt-BR": "Gerar foto de perfil com IA"},
    "Generate New Exercise": {"es": "Generar nuevo ejercicio", "pt-BR": "Gerar novo exercício"},
    "Generate Program": {"es": "Generar programa", "pt-BR": "Gerar programa"},
    "Generate Report": {"es": "Generar reporte", "pt-BR": "Gerar relatório"},
    "Generate a personalized 7-day plan to reduce your wellbeing debt and prevent crashes.": {"es": "Genera un plan personalizado de 7 días para reducir tu deuda de bienestar y prevenir colapsos.", "pt-BR": "Gere um plano personalizado de 7 dias para reduzir sua dívida de bem-estar e prevenir colapsos."},
    "Generate profile picture": {"es": "Generar foto de perfil", "pt-BR": "Gerar foto de perfil"},
    "Generate your first exercise to get started": {"es": "Genera tu primer ejercicio para comenzar", "pt-BR": "Gere seu primeiro exercício para começar"},
    "Generate your first wellness report to see insights about your journey over time.": {"es": "Genera tu primer reporte de bienestar para ver perspectivas sobre tu viaje a lo largo del tiempo.", "pt-BR": "Gere seu primeiro relatório de bem-estar para ver insights sobre sua jornada ao longo do tempo."},
    "Generated %@": {"es": "Generado %@", "pt-BR": "Gerado %@"},
    "Generated profile picture preview": {"es": "Vista previa de foto de perfil generada", "pt-BR": "Visualização de foto de perfil gerada"},
    "Generating art": {"es": "Generando arte", "pt-BR": "Gerando arte"},
    "Generating profile picture": {"es": "Generando foto de perfil", "pt-BR": "Gerando foto de perfil"},
    "Generating your personalized recovery program...": {"es": "Generando tu programa de recuperación personalizado...", "pt-BR": "Gerando seu programa de recuperação personalizado..."},
    "Generating your report...": {"es": "Generando tu reporte...", "pt-BR": "Gerando seu relatório..."},
    "Get notified when your social vitality needs attention, or when supporters want to reach out.": {"es": "Recibe notificaciones cuando tu vitalidad social necesite atención, o cuando los seguidores quieran comunicarse.", "pt-BR": "Seja notificado quando sua vitalidade social precisar de atenção, ou quando apoiadores quiserem entrar em contato."},
    "Get personalized community insights": {"es": "Obtén perspectivas personalizadas de la comunidad", "pt-BR": "Obtenha insights personalizados da comunidade"},
    "Get structured support through major life changes": {"es": "Obtén apoyo estructurado durante cambios importantes de vida", "pt-BR": "Obtenha apoio estruturado durante grandes mudanças de vida"},
    "Gift": {"es": "Regalo", "pt-BR": "Presente"},
    "Gift a subscription": {"es": "Regalar una suscripción", "pt-BR": "Presentear uma assinatura"},
    "Goal %lld": {"es": "Meta %lld", "pt-BR": "Meta %lld"},
    "Good Morning!": {"es": "¡Buenos días!", "pt-BR": "Bom dia!"},
    "Grace Period Active": {"es": "Período de gracia activo", "pt-BR": "Período de graça ativo"},
    "Grant Calendar Access": {"es": "Conceder acceso al calendario", "pt-BR": "Conceder acesso ao calendário"},
    "Great Session!": {"es": "¡Gran sesión!", "pt-BR": "Ótima sessão!"},
    "Great job preparing for sleep. Sweet dreams!": {"es": "¡Excelente trabajo preparándote para dormir. Dulces sueños!", "pt-BR": "Ótimo trabalho se preparando para dormir. Bons sonhos!"},
    "Great job!": {"es": "¡Excelente trabajo!", "pt-BR": "Ótimo trabalho!"},
    
    # H
    "Heart Rate": {"es": "Frecuencia cardíaca", "pt-BR": "Frequência cardíaca"},
    "Heart Rate Variability": {"es": "Variabilidad de frecuencia cardíaca", "pt-BR": "Variabilidade da frequência cardíaca"},
    "Help improve MindFriend for everyone": {"es": "Ayuda a mejorar MindFriend para todos", "pt-BR": "Ajude a melhorar o MindFriend para todos"},
    "Helpful": {"es": "Útil", "pt-BR": "Útil"},
    "Hide Feedback": {"es": "Ocultar comentarios", "pt-BR": "Ocultar feedback"},
    "Hours per week you can mentor": {"es": "Horas por semana que puedes mentorear", "pt-BR": "Horas por semana que você pode mentorar"},
    "How Community Wisdom Works": {"es": "Cómo funciona la sabiduría comunitaria", "pt-BR": "Como a sabedoria comunitária funciona"},
    "How did you sleep last night?": {"es": "¿Cómo dormiste anoche?", "pt-BR": "Como você dormiu ontem à noite?"},
    "How early to deliver calming interventions before stressful events": {"es": "Con cuánta anticipación entregar intervenciones calmantes antes de eventos estresantes", "pt-BR": "Com quanta antecedência entregar intervenções calmantes antes de eventos estressantes"},
    "How effective was this exercise?": {"es": "¿Qué tan efectivo fue este ejercicio?", "pt-BR": "Quão eficaz foi este exercício?"},
    "How much time do you have?": {"es": "¿Cuánto tiempo tienes?", "pt-BR": "Quanto tempo você tem?"},
    "How often to intervene?": {"es": "¿Con qué frecuencia intervenir?", "pt-BR": "Com que frequência intervir?"},
    "How relaxing was this experience?": {"es": "¿Qué tan relajante fue esta experiencia?", "pt-BR": "Quão relaxante foi esta experiência?"},
    "How sensitive should pattern detection be?": {"es": "¿Qué tan sensible debe ser la detección de patrones?", "pt-BR": "Quão sensível deve ser a detecção de padrões?"},
    "How to Progress": {"es": "Cómo progresar", "pt-BR": "Como progredir"},
    "How to reframe it": {"es": "Cómo reformularlo", "pt-BR": "Como reformular"},
    "How was the routine?": {"es": "¿Cómo estuvo la rutina?", "pt-BR": "Como foi a rotina?"},
    "How was this rewrite?": {"es": "¿Cómo estuvo esta reescritura?", "pt-BR": "Como foi esta reescrita?"},
    "How well did you sleep?": {"es": "¿Qué tan bien dormiste?", "pt-BR": "Quão bem você dormiu?"},
    
    # I
    "I'm available to mentor": {"es": "Estoy disponible para mentorear", "pt-BR": "Estou disponível para mentorar"},
    "In-App Messages": {"es": "Mensajes en la app", "pt-BR": "Mensagens no app"},
    "Include Calendar Events": {"es": "Incluir eventos del calendario", "pt-BR": "Incluir eventos do calendário"},
    "Include Metrics": {"es": "Incluir métricas", "pt-BR": "Incluir métricas"},
    "Include my current mood": {"es": "Incluir mi estado de ánimo actual", "pt-BR": "Incluir meu humor atual"},
    "Insights & Next Steps": {"es": "Perspectivas y próximos pasos", "pt-BR": "Insights e próximos passos"},
    "Instruction: %@": {"es": "Instrucción: %@", "pt-BR": "Instrução: %@"},
    "Intervention Delivery": {"es": "Entrega de intervención", "pt-BR": "Entrega de intervenção"},
    "Items identified:": {"es": "Elementos identificados:", "pt-BR": "Itens identificados:"},
    
    # J
    "Journal Prompt": {"es": "Indicación de diario", "pt-BR": "Prompt de diário"},
    "Journaling Prompts": {"es": "Indicaciones de diario", "pt-BR": "Prompts de diário"},
    "Journey Quest": {"es": "Misión del viaje", "pt-BR": "Missão da jornada"},
    
    # K
    "Keep an eye on your top patterns": {"es": "Mantén un ojo en tus patrones principales", "pt-BR": "Fique de olho em seus principais padrões"},
    "Keep chatting! Patterns will show up as you engage.": {"es": "¡Sigue chateando! Los patrones aparecerán a medida que participes.", "pt-BR": "Continue conversando! Os padrões aparecerão conforme você interage."},
    "Keep engaging in circles, and your social vitality score will appear here in a few days!": {"es": "¡Sigue participando en círculos, y tu puntuación de vitalidad social aparecerá aquí en unos días!", "pt-BR": "Continue participando dos círculos, e sua pontuação de vitalidade social aparecerá aqui em alguns dias!"},
    "Keep logging your moods and using wellness features to discover your stress signature.": {"es": "Sigue registrando tus estados de ánimo y usando funciones de bienestar para descubrir tu firma de estrés.", "pt-BR": "Continue registrando seus humores e usando recursos de bem-estar para descobrir sua assinatura de estresse."},
    
    # L
    "LEVEL": {"es": "NIVEL", "pt-BR": "NÍVEL"},
    "LEVEL %lld": {"es": "NIVEL %lld", "pt-BR": "NÍVEL %lld"},
    "Last Night": {"es": "Anoche", "pt-BR": "Ontem à noite"},
    "Last Sync": {"es": "Última sincronización", "pt-BR": "Última sincronização"},
    "Last updated: %@": {"es": "Última actualización: %@", "pt-BR": "Última atualização: %@"},
    "Learn About Thinking Patterns": {"es": "Aprende sobre patrones de pensamiento", "pt-BR": "Aprenda sobre padrões de pensamento"},
    "Learn Your Warning Signs": {"es": "Aprende tus señales de alerta", "pt-BR": "Aprenda seus sinais de alerta"},
    "Learn more": {"es": "Más información", "pt-BR": "Saiba mais"},
    "Learn more about this pattern": {"es": "Más información sobre este patrón", "pt-BR": "Saiba mais sobre este padrão"},
    "Learn more about this thought pattern and reframing techniques": {"es": "Más información sobre este patrón de pensamiento y técnicas de reformulación", "pt-BR": "Saiba mais sobre este padrão de pensamento e técnicas de reformulação"},
    "Learn your unique patterns that appear before stress overwhelms you. This helps MindFriend alert you 24-72 hours before a crisis.": {"es": "Aprende tus patrones únicos que aparecen antes de que el estrés te abrume. Esto ayuda a MindFriend a alertarte 24-72 horas antes de una crisis.", "pt-BR": "Aprenda seus padrões únicos que aparecem antes do estresse sobrecarregá-lo. Isso ajuda o MindFriend a alertá-lo 24-72 horas antes de uma crise."},
    "Learned %@ ago": {"es": "Aprendido hace %@", "pt-BR": "Aprendido há %@"},
    "Learning & Insights": {"es": "Aprendizaje y perspectivas", "pt-BR": "Aprendizado e insights"},
    "Learning your preferences...": {"es": "Aprendiendo tus preferencias...", "pt-BR": "Aprendendo suas preferências..."},
    "Length": {"es": "Duración", "pt-BR": "Duração"},
    "Let the forest surround you": {"es": "Deja que el bosque te rodee", "pt-BR": "Deixe a floresta te envolver"},
    "Let's Go!": {"es": "¡Vamos!", "pt-BR": "Vamos!"},
    "Level %lld → %lld": {"es": "Nivel %lld → %lld", "pt-BR": "Nível %lld → %lld"},
    "LiDAR enables enhanced depth sensing for more accurate object placement.": {"es": "LiDAR permite una detección de profundidad mejorada para una colocación de objetos más precisa.", "pt-BR": "O LiDAR permite detecção de profundidade aprimorada para posicionamento de objetos mais preciso."},
    "Life Transitions": {"es": "Transiciones de vida", "pt-BR": "Transições de vida"},
    "Loading audio...": {"es": "Cargando audio...", "pt-BR": "Carregando áudio..."},
    "Loading debt status...": {"es": "Cargando estado de deuda...", "pt-BR": "Carregando status de dívida..."},
    "Loading events...": {"es": "Cargando eventos...", "pt-BR": "Carregando eventos..."},
    "Loading match details...": {"es": "Cargando detalles de coincidencia...", "pt-BR": "Carregando detalhes da combinação..."},
    "Loading matches...": {"es": "Cargando coincidencias...", "pt-BR": "Carregando combinações..."},
    "Loading mentorships...": {"es": "Cargando mentorías...", "pt-BR": "Carregando mentorias..."},
    "Loading profile...": {"es": "Cargando perfil...", "pt-BR": "Carregando perfil..."},
    "Loading shield history...": {"es": "Cargando historial de escudo...", "pt-BR": "Carregando histórico de escudo..."},
    "Loading strategies": {"es": "Cargando estrategias", "pt-BR": "Carregando estratégias"},
    "Loading transactions...": {"es": "Cargando transacciones...", "pt-BR": "Carregando transações..."},
    "Loading yearly data...": {"es": "Cargando datos anuales...", "pt-BR": "Carregando dados anuais..."},
    "Loading your journey...": {"es": "Cargando tu viaje...", "pt-BR": "Carregando sua jornada..."},
    "Loading your patterns...": {"es": "Cargando tus patrones...", "pt-BR": "Carregando seus padrões..."},
    "Loading your social vitality...": {"es": "Cargando tu vitalidad social...", "pt-BR": "Carregando sua vitalidade social..."},
    "Loading your stories...": {"es": "Cargando tus historias...", "pt-BR": "Carregando suas histórias..."},
    "Log significant life events to understand how they impact your wellness journey.": {"es": "Registra eventos de vida significativos para entender cómo impactan tu viaje de bienestar.", "pt-BR": "Registre eventos de vida significativos para entender como eles impactam sua jornada de bem-estar."},
    "Lookahead Window": {"es": "Ventana de anticipación", "pt-BR": "Janela de antecipação"},
    
    # Days
    "days": {"es": "días", "pt-BR": "dias"},
    "left today": {"es": "restantes hoy", "pt-BR": "restantes hoje"},
    "ms": {"es": "ms", "pt-BR": "ms"},
    "shields": {"es": "escudos", "pt-BR": "escudos"},
    "vs Last Year": {"es": "vs año pasado", "pt-BR": "vs ano passado"},
    "×%@": {"es": "×%@", "pt-BR": "×%@"},
    "• %lld days": {"es": "• %lld días", "pt-BR": "• %lld dias"},
    "• Be specific and actionable": {"es": "• Sé específico y práctico", "pt-BR": "• Seja específico e prático"},
    "• Don't include personal details": {"es": "• No incluyas detalles personales", "pt-BR": "• Não inclua detalhes pessoais"},
    "• Focus on what worked for you": {"es": "• Enfócate en lo que funcionó para ti", "pt-BR": "• Foque no que funcionou para você"},
    
    # Assessment keys
    "assessment.analyzing": {"es": "Analizando...", "pt-BR": "Analisando..."},
    "assessment.error_title": {"es": "Error de evaluación", "pt-BR": "Erro de avaliação"},
    "assessment.submit": {"es": "Enviar", "pt-BR": "Enviar"},
    "assessment.title": {"es": "Evaluación", "pt-BR": "Avaliação"},
    "assessment.type.family": {"es": "Familia", "pt-BR": "Família"},
    "assessment.type.friends": {"es": "Amigos", "pt-BR": "Amigos"},
    "assessment.type.relationships": {"es": "Relaciones", "pt-BR": "Relacionamentos"},
    "assessment.type.work": {"es": "Trabajo", "pt-BR": "Trabalho"},
    "common.back": {"es": "Atrás", "pt-BR": "Voltar"},
    "common.next": {"es": "Siguiente", "pt-BR": "Próximo"},
}

def main():
    # Load xcstrings file
    xcstrings_path = 'apps/ios/MindFriendApp/Resources/Localizable.xcstrings'
    with open(xcstrings_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    strings = data.get('strings', {})
    translated_count = 0
    
    for key, value in strings.items():
        if key in TRANSLATIONS:
            localizations = value.get('localizations', {})
            trans = TRANSLATIONS[key]
            
            # Add Spanish translation
            if 'es' in trans:
                if 'es' not in localizations:
                    localizations['es'] = {}
                localizations['es']['stringUnit'] = {
                    'state': 'translated',
                    'value': trans['es']
                }
            
            # Add Portuguese-BR translation
            if 'pt-BR' in trans:
                if 'pt-BR' not in localizations:
                    localizations['pt-BR'] = {}
                localizations['pt-BR']['stringUnit'] = {
                    'state': 'translated',
                    'value': trans['pt-BR']
                }
            
            value['localizations'] = localizations
            translated_count += 1
    
    # Save updated file
    with open(xcstrings_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    
    print(f"Applied {translated_count} additional translations")
    
    # Count remaining missing
    missing_count = 0
    for key, value in strings.items():
        localizations = value.get('localizations', {})
        es_loc = localizations.get('es', {})
        es_unit = es_loc.get('stringUnit', {})
        if not es_unit.get('value'):
            missing_count += 1
    
    print(f"Still missing: {missing_count} strings")

if __name__ == '__main__':
    main()
