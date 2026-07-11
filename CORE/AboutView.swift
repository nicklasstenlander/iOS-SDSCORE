import SwiftUI
import MapKit

struct AboutView: View {
    private static let schoolCoordinate = CLLocationCoordinate2D(latitude: 59.4290, longitude: 17.9465)
    private static let mapsURL = URL(string: "http://maps.apple.com/?q=Sollentuna%20Dans%20%26%20Scenskola&address=Kuskv%C3%A4gen%206%2C%20191%2062%20Sollentuna&ll=59.4290,17.9465")!
    private static let websiteURL = URL(string: "https://www.sollentunadansochscenskola.se")!

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: schoolCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
    )
    @State private var selectedInstructor: PublicInstructor?

    private let instructors = PublicInstructor.all

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
        .background(Color.sdsPublicBackground.ignoresSafeArea())
        .navigationTitle("Om skolan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedInstructor) { instructor in
            InstructorDetailView(instructor: instructor)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var heroText: some View {
        Text("Mer än bara en dansskola – en trygg och inspirerande plats där du kan utvecklas, hitta dansglädje och växa.")
            .font(SDSType.agrandir(28, weight: .bold))
            .foregroundColor(.sdsTeal)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sdsPublicBackground)
            .overlay(Rectangle().fill(Color.sdsPublicBorder).frame(height: 1), alignment: .bottom)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sollentuna Dans & Scenskola")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsTeal)

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
        .overlay(Rectangle().fill(Color.sdsPublicBorder).frame(height: 1), alignment: .bottom)
    }

    private var instructorsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pedagogerna")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsTeal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 22) {
                ForEach(instructors) { instructor in
                    Button {
                        selectedInstructor = instructor
                    } label: {
                        InstructorCard(instructor: instructor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hitta hit")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsTeal)

            Map(position: $mapPosition) {
                Marker("Sollentuna Dans & Scenskola", coordinate: Self.schoolCoordinate)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Label("Kuskvägen 6, 191 62 Sollentuna", systemImage: "mappin")
                .font(SDSType.agrandir(14))
                .foregroundColor(.sdsPrimaryText)

            Link(destination: Self.mapsURL) {
                Label("Öppna i Apple Maps", systemImage: "map")
                    .font(SDSType.agrandir(15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.sdsPublicSubtleSurface)
                    .foregroundColor(.sdsTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kontakt")
                .font(SDSType.agrandir(22, weight: .bold))
                .foregroundColor(.sdsTeal)

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
            Link(destination: Self.websiteURL) {
                Label("Hemsida", systemImage: "safari")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Text("Telefontid vardagar 10:00–13:00")
            Text("Mån–Fre 15:30–21:30\nLör 9:00–14:00\nSön 9:00–13:00")
            Text("© 2026 Moon Movements AB")
                .foregroundColor(.sdsMutedText)
        }
        .font(SDSType.agrandir(15))
        .foregroundColor(.sdsTeal)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sdsCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sdsBorder, lineWidth: 1))
    }
}

private struct PublicInstructor: Identifiable {
    let name: String
    let role: String
    let bio: String
    let imageURL: URL?
    let isRecruitment: Bool

    var id: String { name }

    init(name: String, role: String, bio: String, imageURL: String? = nil, isRecruitment: Bool = false) {
        self.name = name
        self.role = role
        self.bio = bio
        self.imageURL = imageURL.flatMap(URL.init(string:))
        self.isRecruitment = isRecruitment
    }

    static let all: [PublicInstructor] = [
        PublicInstructor(name: "Madeleine Marquart", role: "Pedagog, ägare", bio: "Madeleine Stenlander Marquart är en erfaren och uppskattad danspedagog, utbildad vid Balettakademien i Stockholm, med över 15 års arbete inom undervisning, koreografi och scenkonst. Hennes distinkta \"Madde-stil\" kännetecknas av teknisk precision, starkt uttryck och scenisk närvaro – och hon är känd för att inspirera dansare att hitta både mod och autenticitet i sitt uttryck.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/b557d476-45cb-4d65-bffd-43674990e326/sds_citystudio_cc_250609-144.jpg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Sofia Östergren", role: "Pedagog, ägare", bio: "Sofia Östergren är en uttrycksfull dansare, koreograf och pedagog med utbildning från Balettakademien i Stockholm, känd för sina berättande koreografier med rötter i jazz och contemporary, där närvaro, känsla och sceniskt djup står i centrum. Hon har lång erfarenhet av att undervisa alla åldrar och hyllas för sin förmåga att kombinera teknik, musikalitet och personligt uttryck – något som också syntes i hennes prisade koreografi för Streetstar Dance School Challenge 2024.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/28a609a9-15df-40d0-9519-7bab5026c332/sds_citystudio_cc_250609-152.jpg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Amanda Lidholm", role: "Pedagog, ägare", bio: "Amanda Lidholm är en internationellt erfaren dansare, koreograf och pedagog utbildad vid Iwanson i München, med stark teknisk grund i samtida dans, jazz och balett samt en karriär som spänner över teater, event och tävlingsdans. Hon är en eftertraktad coach och certifierad domare på både nationell och internationell nivå, känd för sitt tydliga uttryck, sin sceniska precision och sin förmåga att lyfta dansare till nya höjder.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/2fbd6f63-ab40-45d5-838f-799693ff4e44/sds_citystudio_cc_250609-149.jpg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Isabella Svärdstam", role: "Danslärare", bio: "Isabella är utbildad vid Balettakademien och House of Shapes i Stockholm och har specialiserat sig på street och kommersiell dans. Hon brinner för att lyfta fram varje elevs personliga stil och uttryck – alltid med groove, energi och musikalitet i centrum. Hennes klasser kombinerar teknisk träning med sceniskt självförtroende, och passar både nybörjare och mer erfarna dansare.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/07e212cb-7c75-4f03-a39f-6d5ce97c78b2/Isabellasvardstam.JPG"),
        PublicInstructor(name: "Jennifer Lagemyr", role: "Danslärare", bio: "Jennifer är utbildad vid Balettakademien i Stockholm med specialisering inom street- och modern dans. Under sin karriär har hon arbetat som dansare och koreograf i olika föreställningar, events och musikvideos, där hon blandar teknisk precision med kreativt uttryck. Hennes klasser präglas av energi, musikalitet och ett varmt stöd, med fokus på att stärka varje elevs unika stil – oavsett nivå.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/cf248dbf-f32a-4a83-8960-ed6b3d365e31/Jennifer_lagemyr.png?content-type=image%2Fpng"),
        PublicInstructor(name: "Sara Liderfors", role: "Danslärare", bio: "Sara är utbildad professionell dansare på Balettakademien Stockholm då hon gick deras 3-åriga yrkesdansarutbildning. Genom åren har hon gjort ett flertal dansjobb på events, konserter och föreställningar och parallellt jobbat som danslärare. Hon fokuserar framförallt på stilar som heels/heels technique, jazz och kommersiell dans.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/f51d875d-6e73-4452-9a22-97d4b67fbd90/Sara.png?content-type=image%2Fpng"),
        PublicInstructor(name: "Hilda Sahlqvist", role: "Danslärare", bio: "Hilda har dansat sedan barnsben och har genom åren utvecklat en stark och mångsidig stil inom både Street, Commercial, Contemporary och Jazz. Med flera års erfarenhet som danslärare brinner hon för att inspirera sina elever och skapa en trygg och energifylld miljö där alla kan växa – både som dansare och individer.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/730b0f9a-6391-434c-a8a3-75ac9e5bb037/Hilda.png?content-type=image%2Fpng"),
        PublicInstructor(name: "Lova Nygårds", role: "Danslärare", bio: "Lova är en energifylld och engagerad danslärare som brinner för att se sina elever växa genom rörelse, glädje och uttryck. Hennes klasser präglas av högt tempo, positiv energi och en trygg stämning där alla vågar ta plats.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/b9e46441-4e7b-448f-8c79-45d033cc655b/Lova.JPG?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Agnes Holmquist", role: "Assistent", bio: "Agnes har dansat sedan barndomen och har sin bas i Jazz, men behärskar även Contemporary, Street, Commercial och High Heels. Hon är nyligen examinerad från en treårig musikallinje där hon utvecklade sin scennärvaro och känsla för uttryck genom rörelse.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/6ff942c0-d44e-4bae-b97f-ade447c1488f/Agnes.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Alice Birgander", role: "Danslärare", bio: "Alice har dansat så länge hon kan minnas – från barnbalett till modernt, jazz, street, high heels och commercial. Hon har en treårig dansutbildning i flera stilar och undervisar barn 3–13 år i street, jazz, balett och modernt.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/29a9515a-8921-4ffc-89dc-3593982b3f1f/Alice.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Elsa Ershammar", role: "Danslärare", bio: "Elsa är en sprallig och engagerad danslärare som har erfarenhet av att undervisa i stilar som Barnbalett, Barndans, Jazz och Streetdance. På hennes lektioner står dansglädje, gemenskap och nyfikenhet i centrum.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/c1536961-1d1c-4c2c-a73c-2d9f3f10c474/Elsa+.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Viola Skytt", role: "Assistent", bio: "Viola har dansat sedan unga år, med en stark grund i showjazz. Under sin dansresa har hon fördjupat sig i contemporary, street, heels och musikal. De senaste tre åren har hon gått en dans- och musikallinje och utvecklat både teknisk färdighet och scenisk närvaro.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/9bf693c8-434e-421c-9462-00c9b1c661bf/Viola.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Livia Cronheim", role: "Danslärare", bio: "Livia har dansat sedan hon var 2 år gammal och har gått en treårig dansutbildning med fokus på jazz, modernt, balett och commercial. Hon har mycket energi och glädje, och tycker det är otroligt givande att jobba med barn. I danssalen strävar hon efter att alla ska känna sig trygga, sedda och ha riktigt kul tillsammans.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/4e7015b4-dfce-4e73-b2b7-1b6f2990377c/Livia.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Aline Nordenberg", role: "Danslärare", bio: "Aline är en positiv och närvarande person med en lång bakgrund inom dans. Hon är nyligen examinerad från en treårig danslinje. Genom åren har hon utvecklat sina färdigheter inom flera olika stilar, bland annat jazz, street, contemporary och commercial. På hennes lektioner är gemenskap och trygghet viktiga ledord. Aline vill skapa en miljö där alla känner sig välkomna, oavsett erfarenhet. Hon strävar efter att varje deltagare ska känna sig sedd och uppmuntrad och hon hoppas kunna sprida dansglädje till alla i rummet.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/6bf4f12d-5780-4089-aee6-981015b095cc/Aline.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Matilda Lawenius", role: "Danslärare", bio: "Matilda är en varm och engagerad dansare med stor passion för rörelse och utveckling. Hon går just nu sitt sista år på Södra Latins dansutbildning, där hon läser det avancerade programmet och fördjupar sig i både teknik och scenisk förståelse. Under sin utbildning har hon utvecklat sina kunskaper inom flera stilar, bland annat jazz, contemporary, street och commercial.\n\nUtöver sin egen danskarriär har Matilda erfarenhet av att undervisa barn och ungdomar, framför allt i jazz men även i andra stilar. På hennes klasser är gemenskap, trygghet och dansglädje centrala värden. Hon strävar efter att skapa en miljö där alla känner sig välkomna och sedda, oavsett nivå, och där varje deltagare får möjlighet att växa och utmana sig själv.\n\nMatildas mål är att inspirera, stärka och sprida dansens glädje – både i kropp och hjärta.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/7f9b6d89-e5e5-49b6-82e9-14a6757dd6b1/Matilda+Lawenius.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Mila Molander", role: "Danslärare", bio: "Mila har dansat hela sitt liv och är idag en del av Advanced Program Step 2. För henne handlar dans om uttryck, känsla och gemenskap. Utöver sin egen träning undervisar Mila och brinner för att inspirera andra. På hennes klasser ligger fokus på både utveckling och dansglädje, där eleverna får bygga självförtroende och våga ta plats. Det hon tycker mest om är att se sina elever utvecklas och hitta sin egen passion för dans.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/ca5b81cc-cc75-4acd-95e5-8ed2fcc29f28/Mila.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Ellen Kurunmäki", role: "Danslärare", bio: "Ellen är en engagerad och glädjefull dansare. Hon har dansat i många år och fördjupat sig i många av dansens olika stilar. Just nu dansar hon i Advanced Program Step 2 och strävar hela tiden efter att utvecklas vidare och ha kul. Utöver hennes egna danskarriär har Ellen undervisat barn och ungdomar i olika åldrar, stilar och nivåer i flera år. Hon har stora ambitioner inom dansen som hon önskar att dela med sig av på klass. Ellen strävar efter att skapa en trygg miljö och ge utrymme för att utvecklas, ha kul och våga prova nytt.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/7e043cda-5365-456e-a43d-b9e1b17f1188/Ellen.jpg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Freja Karlsson", role: "Assistent", bio: "Freja älskar att dansa eftersom det ger henne möjlighet att uttrycka sina känslor, känna gemenskap, ha roligt och samtidigt vara i rörelse. Dans har varit en stor del av hennes liv under lång tid, vilket gör det extra roligt för henne att få undervisa andra som delar samma intresse. Hon tycker om att stötta eleverna, se dem utvecklas och skapa en miljö där de kan ha riktigt kul under lektionerna. Det bästa med att undervisa, enligt Freja, är att få vara en del av elevernas dansglädje och se hur mycket nytt de lär sig varje gång.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/cc7b221c-bcce-4895-8d93-3fbb73cd7c90/Freja+assistent+.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Evelyn Smeds", role: "Assistent", bio: "Evelyn har alltid haft dansen som en viktig del av sitt liv och hon älskar att uttrycka känslor genom rörelse. För henne har gemenskapen och dansglädjen alltid stått i centrum, vilket också gör undervisningen extra meningsfull. Att få se eleverna utvecklas och hur deras glädje för dans växer är något hon upplever som otroligt givande. Det allra finaste, tycker hon, är att få följa deras resa och se hur de steg för steg blir tryggare och mer hemma i danssalen.", imageURL: "https://images.squarespace-cdn.com/content/68093bdd8e42fd6c032c5835/c7b7d271-016a-45d8-9a9e-df6f5484be55/eveelyn+assistent+.jpeg?content-type=image%2Fjpeg"),
        PublicInstructor(name: "Är detta du?", role: "Vi söker fler danslärare & assistenter", bio: "Brinner du för dans, pedagogik och att skapa trygga rum där barn och unga kan utvecklas? Tycker du att vår studio känns som ett ställe där du skulle trivas – både i danssalen och i gemenskapen?\n\nSkicka ett mail och berätta kort om dig själv, din bakgrund och vilka stilar du undervisar i: info@sollentunadansochscenskola.se", isRecruitment: true)
    ]
}

private struct InstructorCard: View {
    let instructor: PublicInstructor

    var body: some View {
        VStack(spacing: 10) {
            InstructorPortrait(instructor: instructor, size: 136)

            VStack(spacing: 3) {
                Text(instructor.name)
                    .font(SDSType.agrandir(14, weight: .bold))
                    .foregroundColor(.sdsPrimaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(instructor.role)
                    .font(SDSType.agrandir(12))
                    .foregroundColor(.sdsSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 210, alignment: .top)
        .padding(.vertical, 6)
    }
}

private struct InstructorDetailView: View {
    let instructor: PublicInstructor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 16) {
                        InstructorPortrait(instructor: instructor, size: 104)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(instructor.name)
                                .font(SDSType.agrandir(24, weight: .bold))
                                .foregroundColor(.sdsTeal)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(instructor.role)
                                .font(SDSType.agrandir(15, weight: .bold))
                                .foregroundColor(.sdsSecondaryText)
                        }
                    }

                    Text(instructor.bio)
                        .font(SDSType.agrandir(15))
                        .foregroundColor(.sdsPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if instructor.isRecruitment {
                        Link(destination: URL(string: "mailto:info@sollentunadansochscenskola.se")!) {
                            Label("Mejla oss", systemImage: "envelope")
                                .font(SDSType.agrandir(16, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.sdsDarkGreen)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.sdsPublicBackground.ignoresSafeArea())
            .navigationTitle("Pedagog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
        }
    }
}

private struct InstructorPortrait: View {
    let instructor: PublicInstructor
    let size: CGFloat

    var body: some View {
        ZStack {
            if let imageURL = instructor.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .saturation(instructor.isRecruitment ? 1 : 0)
        .overlay(Circle().stroke(Color.sdsPublicBorder, lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(instructor.isRecruitment ? Color.black : Color.sdsPublicSubtleSurface)
            Text(instructor.isRecruitment ? "Är detta\ndu?" : String(instructor.name.prefix(1)))
                .font(SDSType.agrandir(instructor.isRecruitment ? size * 0.16 : size * 0.34, weight: .bold))
                .foregroundColor(instructor.isRecruitment ? .white : .sdsTeal)
                .multilineTextAlignment(.center)
                .padding(8)
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
