import Foundation

@MainActor
final class Store: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selection: Project.ID?

    init() {
        load()
        selection = projects.first?.id
    }

    var selected: Project? {
        guard let selection else { return nil }
        return projects.first { $0.id == selection }
    }

    func load() {
        guard let data = try? Data(contentsOf: Paths.projectsFile) else { return }
        projects = (try? JSONDecoder().decode([Project].self, from: data)) ?? []
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(projects) else { return }
        Paths.writeAtomically(data, to: Paths.projectsFile)
    }

    func add(_ project: Project) {
        projects.append(project)
        selection = project.id
        save()
    }

    func update(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        save()
    }

    func remove(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if selection == project.id { selection = projects.first?.id }
        save()
    }

    func move(_ project: Project, to index: Int) {
        guard let from = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let target = max(0, min(projects.count - 1, index))
        guard from != target else { return }
        let item = projects.remove(at: from)
        projects.insert(item, at: target)
        save()
    }

    func upsert(_ service: Service, in project: Project) {
        guard var copy = projects.first(where: { $0.id == project.id }) else { return }
        if let index = copy.services.firstIndex(where: { $0.id == service.id }) {
            copy.services[index] = service
        } else {
            copy.services.append(service)
        }
        update(copy)
    }

    func removeService(_ service: Service, from project: Project) {
        guard var copy = projects.first(where: { $0.id == project.id }) else { return }
        copy.services.removeAll { $0.id == service.id }
        update(copy)
    }

    /// What a folder obviously runs — offered when a project is added, never
    /// applied behind the user's back.
    static func detectServices(at path: String) -> [Service] {
        let fm = FileManager.default
        var found: [Service] = []

        let packageURL = URL(fileURLWithPath: path).appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: packageURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: Any] {
            let runner = fm.fileExists(atPath: path + "/pnpm-lock.yaml") ? "pnpm"
                : fm.fileExists(atPath: path + "/yarn.lock") ? "yarn"
                : fm.fileExists(atPath: path + "/bun.lockb") ? "bun" : "npm"
            for key in ["dev", "start", "serve", "watch"] where scripts[key] != nil {
                let command = runner == "npm" ? "npm run \(key)" : "\(runner) run \(key)"
                found.append(Service(name: key, command: command))
            }
        }

        if fm.fileExists(atPath: path + "/artisan") {
            found.append(Service(name: "serve", command: "php artisan serve"))
            if fm.fileExists(atPath: path + "/config/horizon.php") {
                found.append(Service(name: "horizon", command: "php artisan horizon"))
            } else {
                found.append(Service(name: "queue", command: "php artisan queue:work"))
            }
        }

        if fm.fileExists(atPath: path + "/manage.py") {
            found.append(Service(name: "runserver", command: "python manage.py runserver"))
        }
        if fm.fileExists(atPath: path + "/docker-compose.yml")
            || fm.fileExists(atPath: path + "/compose.yaml") {
            found.append(Service(name: "compose", command: "docker compose up"))
        }
        return found
    }
}
