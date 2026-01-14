# MindFriend Feature Specifications

This folder contains detailed specifications for future features designed to improve retention, growth, and user experience.

## Priority Order

| Priority | Feature             | Spec                                                     | Impact                          |
| -------- | ------------------- | -------------------------------------------------------- | ------------------------------- |
| P1       | AI Memory           | [01-ai-memory.md](./01-ai-memory.md)                     | Differentiation, emotional hook |
| P2       | Onboarding          | [02-onboarding.md](./02-onboarding.md)                   | Fixes day-1 drop-off            |
| P3       | Circle Virality     | [03-circle-virality.md](./03-circle-virality.md)         | Growth AND retention            |
| P4       | Smart Notifications | [04-smart-notifications.md](./04-smart-notifications.md) | Brings users back               |
| P5       | Progression System  | [05-progression-system.md](./05-progression-system.md)   | Long-term retention             |
| P6       | Weekly Insights     | [06-weekly-insights.md](./06-weekly-insights.md)         | Value that compounds            |
| P7       | Credibility Signals | [07-credibility-signals.md](./07-credibility-signals.md) | Trust building                  |
| P8       | Monetization        | [08-monetization.md](./08-monetization.md)               | Revenue optimization            |
| Future   | Voice Mode          | [09-voice-mode.md](./09-voice-mode.md)                   | Big bet differentiator          |

## Spec Template

Each spec follows a consistent structure:

1. **Overview** - What and why
2. **User Stories** - Who benefits and how
3. **Product Requirements** - MVP vs V2 vs Out of Scope
4. **Technical Design** - Database, iOS, Backend changes
5. **UI/UX** - Screen flows and interactions
6. **Verification** - How to test
7. **Dependencies** - What must exist first
8. **Risks & Mitigations** - What could go wrong

## Implementation Notes

- All database changes require migrations in `supabase/migrations/`
- iOS changes follow existing patterns in `apps/ios/MindFriendApp/`
- Edge Functions live in `supabase/functions/`
- RLS policies required for all new tables

## Related Documents

- [SCRATCHPAD.md](../SCRATCHPAD.md) - Original feature ideas
- [CLAUDE.md](../CLAUDE.md) - Architecture guidelines
- [MindFriend-spec.md](../MindFriend-spec.md) - MVP specification
