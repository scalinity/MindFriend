private var needsGrid: some View {
        let needs = assessment.topNeeds
        
        return VStack(spacing: 12) {
            Text("Top Identified Needs")
                .font(.headline)
            
            if needs.isEmpty {
                Text("No significant needs identified yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(needs, id: \.id) { need in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(need.description)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack(spacing: 8) {
                            Text(need.category)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                            
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }