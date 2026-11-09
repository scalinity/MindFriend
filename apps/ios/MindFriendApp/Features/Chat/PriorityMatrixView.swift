private var needsGrid: some View {
        let needs = assessment.topNeeds

        return VStack(spacing: SupportTheme.Spacing.s) {
            Text("Top Identified Needs")
                .font(.headline)

            if needs.isEmpty {
                Text("No significant needs identified yet")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            } else {
                ForEach(needs, id: \.id) { need in
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(need.description)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Text(need.category)
                                .font(.caption)
                                .padding(.horizontal, SupportTheme.Spacing.xs)
                                .padding(.vertical, SupportTheme.Spacing.xxs)
                                .background(SupportTheme.field)
                                .foregroundStyle(SupportTheme.accent)
                                .clipShape(Capsule())

                            Spacer()
                        }
                    }
                    .padding()
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
            }
        }
    }
