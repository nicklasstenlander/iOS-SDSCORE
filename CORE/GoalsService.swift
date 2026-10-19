import Foundation
import Combine

enum GoalMetric: String, Codable, CaseIterable {
    case bookingsCount = "bookings_count"
    case acceptedCount = "accepted_count"
    case revenue
    case occupancy
    case newStudents = "new_students"
}

struct Goal: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String?
    let metric: GoalMetric
    let target: Double
    let eventBlockId: String?
    let eventKey: String?
    let deadline: String
    let createdAt: String?
    let updatedAt: String?
    let archived: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case metric
        case target
        case eventBlockId = "event_block_id"
        case eventKey = "event_key"
        case deadline
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archived
    }
}

struct CreateGoalInput: Codable {
    let title: String
    let description: String?
    let metric: GoalMetric
    let target: Double
    let eventBlockId: String?
    let eventKey: String?
    let deadline: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case metric
        case target
        case eventBlockId = "event_block_id"
        case eventKey = "event_key"
        case deadline
    }
}

@MainActor
final class GoalsService: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let proxyURL = URL(string: "https://sds-cogwork-proxy.nicklas-stenlander.workers.dev")!

    func loadGoals() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let url = proxyURL.appending(path: "goals")
            let request = try APIClient.request(url: url)
            goals = try await APIClient.json([Goal].self, for: request)
        } catch {
            errorMessage = "Kunde inte hämta mål. \(Self.readableErrorMessage(error))"
        }
    }

    func createGoal(_ input: CreateGoalInput) async -> Goal? {
        await sendGoalRequest(path: "goals", method: "POST", input: input)
    }

    func updateGoal(id: Int, input: CreateGoalInput) async -> Goal? {
        await sendGoalRequest(path: "goals/\(id)", method: "PUT", input: input)
    }

    func deleteGoal(id: Int) async {
        errorMessage = nil
        do {
            var request = URLRequest(url: proxyURL.appending(path: "goals/\(id)"))
            request.httpMethod = "DELETE"
            _ = try await APIClient.data(for: request)
            goals.removeAll { $0.id == id }
        } catch {
            errorMessage = "Kunde inte ta bort mål. \(Self.readableErrorMessage(error))"
        }
    }

    private func sendGoalRequest(path: String, method: String, input: CreateGoalInput) async -> Goal? {
        errorMessage = nil

        do {
            var request = URLRequest(url: proxyURL.appending(path: path))
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(input)

            let goal = try await APIClient.json(Goal.self, for: request)
            await loadGoals()
            return goal
        } catch {
            errorMessage = "Kunde inte spara mål. \(Self.readableErrorMessage(error))"
            return nil
        }
    }

    private static func readableErrorMessage(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else { return error.localizedDescription }
        return apiError.localizedDescription
    }
}
