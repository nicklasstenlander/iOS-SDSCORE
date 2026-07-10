import SwiftUI
import MapKit

struct AboutView: View {
    private static let schoolCoordinate = CLLocationCoordinate2D(latitude: 59.4290, longitude: 17.9465)

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: schoolCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
    )

    private let instructors = [
        "Caroline Holmberg",
        "Emma Nordin",
        "Filippa Backman",
        "Julia Bengtsson",
        "Mikaela Larsson",
        "Sofie Andersson"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroText
                aboutSection
                instructorsSection
                mapSection
                contactSection
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .background(Color.sdsBackground.ignoresSafeArea())
        .navigationTitle("Om skolan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroText: some View {
        Text("Mer än bara en dansskola – en trygg och inspirerande plats där du kan utvecklas, hitta dansglädje och växa.")
            .font(SDSType.agrandir(28, weight: .bold))
            .foregroundColor(.sdsDarkGreen)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sdsLightGreenSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sollentuna Dans & Scenskola")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsDarkGreen)

            Text("Vi startade vår dansskola av en enkel men stark drivkraft – att skapa en plats där rörelseglädje, gemenskap och personlig utveckling får ta plats genom dans. Idén föddes ur en längtan efter att erbjuda något mer än bara lektioner.")
                .font(SDSType.agrandir(15))
                .foregroundColor(.sdsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Sollentuna Dans & Scenskola är mer än bara en plats för träning. Det är en miljö där du får utvecklas i din takt, i sällskap med engagerade lärare och likasinnade elever.")
                .font(SDSType.agrandir(15))
                .foregroundColor(.sdsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Color.sdsCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sdsBorder, lineWidth: 1))
    }

    private var instructorsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pedagogerna")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsDarkGreen)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(instructors, id: \.self) { instructor in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.sdsMidGreen)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Text(String(instructor.prefix(1)))
                                    .font(SDSType.agrandir(14, weight: .bold))
                                    .foregroundColor(.sdsDarkGreen)
                            )
                        Text(instructor)
                            .font(SDSType.agrandir(14, weight: .bold))
                            .foregroundColor(.sdsPrimaryText)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.sdsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sdsBorder, lineWidth: 1))
                }
            }
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hitta hit")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsDarkGreen)

            Map(position: $mapPosition) {
                Marker("Sollentuna Dans & Scenskola", coordinate: Self.schoolCoordinate)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Label("Kuskvägen 6, 191 62 Sollentuna", systemImage: "mappin")
                .font(SDSType.agrandir(14))
                .foregroundColor(.sdsPrimaryText)
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kontakt")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsDarkGreen)

            Link(destination: URL(string: "tel:0850278989")!) {
                Label("Ring oss", systemImage: "phone")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Link(destination: URL(string: "mailto:info@sollentunadansochscenskola.se")!) {
                Label("Mejla oss", systemImage: "envelope")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Link(destination: URL(string: "https://instagram.com/sollentunadansochscenskola")!) {
                Label("Instagram", systemImage: "camera")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Text("Telefontid vardagar 10:00–13:00")
            Text("Mån–Fre 15:30–21:30\nLör 9:00–14:00\nSön 9:00–13:00")
            Text("© 2026 Moon Movements AB")
                .foregroundColor(.sdsMutedText)
        }
        .font(SDSType.agrandir(15))
        .foregroundColor(.sdsDarkGreen)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sdsCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sdsBorder, lineWidth: 1))
    }
}
