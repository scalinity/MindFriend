"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const client_1 = require("@prisma/client");
const adapter_pg_1 = require("@prisma/adapter-pg");
const adapter = new adapter_pg_1.PrismaPg({
    connectionString: process.env.DATABASE_URL,
});
const prisma = new client_1.PrismaClient({ adapter });
async function main() {
    console.log('🌱 Starting seed...');
    console.log('Creating quest templates...');
    const questTemplates = [
        {
            type: 'breathing',
            title: 'Box Breathing',
            description: 'A calming 4-4-4-4 breathing exercise to reduce stress and center yourself',
            estimatedMinutes: 5,
            difficulty: 1,
            tags: ['stress-relief', 'calming', 'quick'],
            instructionsJson: {
                steps: [
                    {
                        instruction: 'Find a comfortable seated position',
                        durationSeconds: 10,
                    },
                    {
                        instruction: 'Inhale slowly for 4 counts',
                        durationSeconds: 4,
                        type: 'inhale',
                    },
                    {
                        instruction: 'Hold your breath for 4 counts',
                        durationSeconds: 4,
                        type: 'hold',
                    },
                    {
                        instruction: 'Exhale slowly for 4 counts',
                        durationSeconds: 4,
                        type: 'exhale',
                    },
                    {
                        instruction: 'Hold empty for 4 counts',
                        durationSeconds: 4,
                        type: 'hold',
                    },
                ],
                repeatCycles: 5,
                completionMessage: 'Great job! Notice how you feel now compared to before.',
            },
        },
        {
            type: 'walk',
            title: 'Mindful Walk',
            description: 'A short mindful walk outside to clear your mind and get moving',
            estimatedMinutes: 10,
            difficulty: 1,
            tags: ['movement', 'outdoors', 'mindfulness'],
            instructionsJson: {
                steps: [
                    {
                        instruction: 'Step outside and stand still for a moment',
                        durationSeconds: 30,
                    },
                    {
                        instruction: 'Begin walking at a comfortable pace',
                        durationSeconds: 0,
                    },
                    { instruction: 'Notice 5 things you can see', durationSeconds: 60 },
                    { instruction: 'Notice 4 things you can hear', durationSeconds: 60 },
                    { instruction: 'Notice 3 things you can feel', durationSeconds: 60 },
                    {
                        instruction: 'Continue walking and just be present',
                        durationSeconds: 300,
                    },
                ],
                completionMessage: 'Well done! Movement and fresh air do wonders for the mind.',
            },
        },
        {
            type: 'journal',
            title: 'Gratitude Journal',
            description: "Write down three things you're grateful for today",
            estimatedMinutes: 5,
            difficulty: 1,
            tags: ['gratitude', 'reflection', 'writing'],
            instructionsJson: {
                steps: [
                    {
                        instruction: 'Find a quiet spot and take a few deep breaths',
                        durationSeconds: 30,
                    },
                    { instruction: 'Think about your day so far', durationSeconds: 30 },
                    {
                        instruction: "Write down 3 things you're grateful for",
                        durationSeconds: 180,
                        type: 'input',
                    },
                ],
                prompts: [
                    'What made you smile today?',
                    'Who are you grateful to have in your life?',
                    'What simple pleasure did you enjoy recently?',
                ],
                completionMessage: 'Practicing gratitude rewires your brain for positivity.',
            },
        },
        {
            type: 'focus',
            title: 'Pomodoro Focus',
            description: '25 minutes of focused work followed by a 5-minute break',
            estimatedMinutes: 30,
            difficulty: 2,
            tags: ['productivity', 'focus', 'work'],
            instructionsJson: {
                steps: [
                    { instruction: 'Choose one task to focus on', durationSeconds: 30 },
                    {
                        instruction: 'Put your phone on do not disturb',
                        durationSeconds: 15,
                    },
                    {
                        instruction: 'Work on your task with full attention',
                        durationSeconds: 1500,
                        type: 'timer',
                    },
                    {
                        instruction: 'Take a 5-minute break - stretch, walk, rest your eyes',
                        durationSeconds: 300,
                        type: 'break',
                    },
                ],
                completionMessage: 'You did it! Focused work is a superpower.',
            },
        },
        {
            type: 'gratitude',
            title: 'Kindness Note',
            description: 'Send a message of appreciation to someone in your life',
            estimatedMinutes: 5,
            difficulty: 1,
            tags: ['gratitude', 'connection', 'kindness'],
            instructionsJson: {
                steps: [
                    {
                        instruction: 'Think of someone who has helped or supported you recently',
                        durationSeconds: 30,
                    },
                    {
                        instruction: 'Write a short message expressing your appreciation',
                        durationSeconds: 180,
                        type: 'input',
                    },
                    {
                        instruction: 'Send the message (text, email, or in-person)',
                        durationSeconds: 60,
                    },
                ],
                prompts: [
                    'Thank them for something specific',
                    'Tell them how their actions made you feel',
                    'Keep it genuine and from the heart',
                ],
                completionMessage: 'Spreading kindness benefits both you and the recipient!',
            },
        },
        {
            type: 'stretch',
            title: 'Desk Stretches',
            description: 'A quick stretching routine to release tension from sitting',
            estimatedMinutes: 5,
            difficulty: 1,
            tags: ['movement', 'stretching', 'desk-friendly'],
            instructionsJson: {
                steps: [
                    {
                        instruction: 'Neck rolls - slowly roll your head in circles',
                        durationSeconds: 30,
                    },
                    {
                        instruction: 'Shoulder shrugs - raise and lower your shoulders',
                        durationSeconds: 20,
                    },
                    {
                        instruction: 'Seated spinal twist - twist gently to each side',
                        durationSeconds: 40,
                    },
                    {
                        instruction: 'Wrist circles - rotate your wrists both directions',
                        durationSeconds: 20,
                    },
                    {
                        instruction: 'Chest opener - clasp hands behind back and stretch',
                        durationSeconds: 30,
                    },
                    {
                        instruction: 'Forward fold - stand and fold forward, let arms hang',
                        durationSeconds: 30,
                    },
                ],
                completionMessage: 'Your body thanks you! Regular stretching prevents tension buildup.',
            },
        },
    ];
    await prisma.questTemplate.deleteMany({});
    await prisma.questTemplate.createMany({
        data: questTemplates,
    });
    console.log(`✅ Created ${questTemplates.length} quest templates`);
    console.log('Creating badges...');
    const badges = [
        {
            code: 'first_quest',
            title: 'Quest Beginner',
            description: 'Complete your first daily quest',
            criteriaJson: { type: 'quest_count', threshold: 1 },
        },
        {
            code: 'first_chat',
            title: 'Conversation Starter',
            description: 'Have your first conversation with your AI companion',
            criteriaJson: { type: 'chat_count', threshold: 1 },
        },
        {
            code: 'streak_3',
            title: '3-Day Streak',
            description: 'Complete quests 3 days in a row',
            criteriaJson: { type: 'streak', threshold: 3 },
        },
        {
            code: 'streak_7',
            title: 'Week Warrior',
            description: 'Complete quests 7 days in a row',
            criteriaJson: { type: 'streak', threshold: 7 },
        },
        {
            code: 'streak_14',
            title: 'Fortnight Focus',
            description: 'Complete quests 14 days in a row',
            criteriaJson: { type: 'streak', threshold: 14 },
        },
        {
            code: 'streak_30',
            title: 'Monthly Master',
            description: 'Complete quests 30 days in a row',
            criteriaJson: { type: 'streak', threshold: 30 },
        },
        {
            code: 'mood_tracker',
            title: 'Mood Tracker',
            description: 'Log your mood 7 times',
            criteriaJson: { type: 'mood_count', threshold: 7 },
        },
        {
            code: 'circle_creator',
            title: 'Circle Creator',
            description: 'Create your first friend circle',
            criteriaJson: { type: 'circle_created', threshold: 1 },
        },
    ];
    for (const badge of badges) {
        await prisma.badge.upsert({
            where: { code: badge.code },
            update: badge,
            create: badge,
        });
    }
    console.log(`✅ Created ${badges.length} badges`);
    console.log('Creating exercises...');
    const exercises = [
        {
            type: 'breathing',
            title: '4-7-8 Relaxation Breath',
            description: 'A calming technique that helps reduce anxiety and promote sleep',
            durationSeconds: 300,
            contentKind: 'text',
            contentText: `The 4-7-8 breathing technique is a powerful relaxation method.

1. Exhale completely through your mouth, making a whoosh sound.
2. Close your mouth and inhale quietly through your nose for 4 counts.
3. Hold your breath for 7 counts.
4. Exhale completely through your mouth for 8 counts.
5. Repeat this cycle 3-4 times.

This pattern acts as a natural tranquilizer for the nervous system.`,
            tags: ['relaxation', 'sleep', 'anxiety'],
        },
        {
            type: 'meditation',
            title: 'Body Scan Meditation',
            description: 'A guided practice to release tension throughout your body',
            durationSeconds: 600,
            contentKind: 'text',
            contentText: `Find a comfortable position lying down or seated.

Close your eyes and take three deep breaths.

Starting at the top of your head, notice any sensations.
Slowly move your attention down to your forehead, eyes, jaw.
Release any tension you find.

Continue to your neck and shoulders - common tension spots.
Let them soften and relax.

Move down through your arms, hands, and fingers.
Notice the sensations without judgment.

Bring awareness to your chest and belly.
Feel them rise and fall with each breath.

Continue to your lower back, hips, and legs.
All the way down to your feet and toes.

Take a moment to feel your whole body at once.
Notice the sense of relaxation throughout.`,
            tags: ['relaxation', 'body-awareness', 'stress-relief'],
        },
        {
            type: 'grounding',
            title: '5-4-3-2-1 Grounding',
            description: 'A sensory awareness exercise to bring you back to the present',
            durationSeconds: 300,
            contentKind: 'text',
            contentText: `When anxiety takes over, this exercise grounds you in the present moment.

Take a slow, deep breath.

Name 5 things you can SEE around you.
(Look for details you usually miss)

Name 4 things you can TOUCH or FEEL.
(Notice textures, temperatures, sensations)

Name 3 things you can HEAR.
(Listen for distant and nearby sounds)

Name 2 things you can SMELL.
(Or 2 smells you like)

Name 1 thing you can TASTE.
(Or something you'd like to taste)

Take another deep breath. You are here, in this moment, and you are safe.`,
            tags: ['anxiety', 'grounding', 'mindfulness'],
        },
        {
            type: 'affirmation',
            title: 'Morning Affirmations',
            description: 'Start your day with positive self-affirmations',
            durationSeconds: 180,
            contentKind: 'text',
            contentText: `Repeat each affirmation slowly, feeling its meaning:

"I am worthy of love and respect."

"I have the power to create change in my life."

"I am capable of achieving my goals."

"I choose to focus on what I can control."

"I am grateful for this new day and its possibilities."

"I release what no longer serves me."

"I am enough, exactly as I am."

Carry these truths with you throughout your day.`,
            tags: ['positivity', 'morning', 'self-esteem'],
        },
        {
            type: 'visualization',
            title: 'Safe Place Visualization',
            description: 'Create and visit a peaceful mental sanctuary',
            durationSeconds: 480,
            contentKind: 'text',
            contentText: `Close your eyes and take several slow breaths.

Imagine a place where you feel completely safe and at peace.
This can be real or imaginary - a beach, forest, cozy room, or anywhere.

See this place in detail. What does it look like?
Notice the colors, shapes, and light.

What sounds are present? Perhaps waves, birds, or peaceful silence.

Feel the temperature. Is it warm sunshine or cool shade?

What textures surround you? Soft grass, warm sand, comfortable cushions?

Breathe in the air of this place. What does it smell like?

Know that you can return here whenever you need.
This safe place lives within you always.

When ready, slowly bring your awareness back to the present.`,
            tags: ['visualization', 'relaxation', 'safe-space'],
        },
    ];
    await prisma.exercise.deleteMany({});
    await prisma.exercise.createMany({
        data: exercises,
    });
    console.log(`✅ Created ${exercises.length} exercises`);
    console.log('Creating crisis resources...');
    const crisisResources = [
        {
            countryCode: 'US',
            name: '988 Suicide & Crisis Lifeline',
            contact: '988',
            kind: 'phone',
            description: 'Free, confidential support 24/7 for people in distress',
            priority: 1,
        },
        {
            countryCode: 'US',
            name: 'Crisis Text Line',
            contact: 'Text HOME to 741741',
            kind: 'text',
            description: 'Free, 24/7 support via text message',
            priority: 2,
        },
        {
            countryCode: 'US',
            name: 'SAMHSA National Helpline',
            contact: '1-800-662-4357',
            kind: 'phone',
            description: 'Treatment referral service for mental health and substance use',
            priority: 3,
        },
        {
            countryCode: 'GB',
            name: 'Samaritans',
            contact: '116 123',
            kind: 'phone',
            description: 'Free, 24/7 emotional support',
            priority: 1,
        },
        {
            countryCode: 'GB',
            name: 'Shout',
            contact: 'Text SHOUT to 85258',
            kind: 'text',
            description: 'Free, confidential, 24/7 text support',
            priority: 2,
        },
        {
            countryCode: 'GB',
            name: 'Mind Infoline',
            contact: '0300 123 3393',
            kind: 'phone',
            description: 'Mental health information and support',
            priority: 3,
        },
        {
            countryCode: 'CA',
            name: 'Talk Suicide Canada',
            contact: '988',
            kind: 'phone',
            description: '24/7 suicide crisis helpline',
            priority: 1,
        },
        {
            countryCode: 'CA',
            name: 'Crisis Text Line',
            contact: 'Text HOME to 686868',
            kind: 'text',
            description: 'Free, 24/7 support via text message',
            priority: 2,
        },
        {
            countryCode: 'AU',
            name: 'Lifeline Australia',
            contact: '13 11 14',
            kind: 'phone',
            description: '24/7 crisis support and suicide prevention',
            priority: 1,
        },
        {
            countryCode: 'AU',
            name: 'Beyond Blue',
            contact: '1300 22 4636',
            kind: 'phone',
            description: 'Support for anxiety, depression, and suicide prevention',
            priority: 2,
        },
        {
            countryCode: 'AU',
            name: 'Lifeline Text',
            contact: 'Text 0477 13 11 14',
            kind: 'text',
            description: 'Text-based crisis support',
            priority: 3,
        },
        {
            countryCode: 'GLOBAL',
            name: 'International Association for Suicide Prevention',
            contact: 'https://www.iasp.info/resources/Crisis_Centres/',
            kind: 'website',
            description: 'Directory of crisis centers worldwide',
            priority: 1,
        },
        {
            countryCode: 'GLOBAL',
            name: 'Befrienders Worldwide',
            contact: 'https://www.befrienders.org/find-a-helpline',
            kind: 'website',
            description: 'Find emotional support helplines by country',
            priority: 2,
        },
    ];
    await prisma.crisisResource.deleteMany({});
    await prisma.crisisResource.createMany({
        data: crisisResources,
    });
    console.log(`✅ Created ${crisisResources.length} crisis resources`);
    console.log('🎉 Seed completed successfully!');
}
main()
    .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
})
    .finally(async () => {
    await prisma.$disconnect();
});
//# sourceMappingURL=seed.js.map