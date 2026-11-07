// Compile alongside the production InterventionEfficacyModels and EfficacyCalculator.
import Foundation

@main struct EfficacyParityCheck {
    struct Fixture: Decodable { let name: String; let scores: [Double]; let efficacyScore: Double }
    static func main() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        for fixture in fixtures {
            let trajectory = fixture.scores.enumerated().map { index, score in
                TrajectoryPoint(id: UUID(), timestamp: Date(timeIntervalSince1970: Double(index * 30)), secondsFromStart: index * 30, nervousSystemState: nil, emotionClassification: nil, hrvReading: nil, compositeScore: score)
            }
            guard let result = EfficacyCalculator().calculateEfficacy(trajectory: trajectory, sessionDuration: Double((trajectory.count - 1) * 30)), abs(result.efficacyScore - fixture.efficacyScore) < 1e-10 else {
                fatalError("Efficacy parity failed: \(fixture.name)")
            }
            print("PASS \(fixture.name): \(result.efficacyScore)")
        }
    }
}
