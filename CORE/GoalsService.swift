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
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            goals = try JSONDecoder().decode([Goal].self, from: data)
        } catch {
            errorMessage = "Kunde inte hämta mål. \(error.localizedDescription)"
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
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            goals.removeAll { $0.id == id }
        } catch {
            errorMessage = "Kunde inte ta bort mål. \(error.localizedDescription)"
        }
    }

    private func sendGoalRequest(path: String, method: String, input: CreateGoalInput) async -> Goal? {
        errorMessage = nil

        do {
            var request = URLRequest(url: proxyURL.appending(path: path))
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(input)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let goal = try JSONDecoder().decode(Goal.self, from: data)
            await loadGoals()
            return goal
        } catch {
            errorMessage = "Kunde inte spara mål. \(error.localizedDescription)"
            return nil
        }
    }
}
