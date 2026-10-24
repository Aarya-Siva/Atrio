import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var detailIconSize = 28
    @State private var showSettings = false
    let startMeasurement: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brand.padding(.bottom, 24)

                Text("Understand your heart rhythm")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.heading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Use your iPhone camera to capture your pulse and explore heart rhythm patterns in about 30 seconds.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                assetImage("AtrioHero")
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(1.35, contentMode: .fit)
                    .mask(LinearGradient(stops: [.init(color: .white, location: 0),
                                                 .init(color: .white, location: 0.88),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    .accessibilityLabel("Illustration of a fingertip covering a rear camera lens beside the separate flashlight, alongside an anatomical heart.")

                measurementDetails.padding(.bottom, 24)

                PrimaryButton(title: "Start Measurement", systemImage: "waveform.path.ecg", action: startMeasurement)
                    .accessibilityIdentifier("startMeasurementButton")
                    .accessibilityHint("Opens the preparation screen")

                Text("Uses your camera and flashlight · Approximately 30 seconds")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                Text("Atrio cannot diagnose or rule out AFib. An ECG is needed to confirm a rhythm diagnosis.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Home")
        .sheet(isPresented: $showSettings) { AtrioSettingsView() }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            assetImage("AtrioMark")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text("Atrio")
                .font(AppTypography.brand)
                .foregroundStyle(AppColors.accent)
            Spacer(minLength: 12)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("homeSettingsButton")
        }
    }

    private var measurementDetails: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            measurementDetail(symbol: "clock", title: "30-second scan", detail: "Fingertip recording")
            measurementDetail(symbol: "lock", title: "On-device privacy", detail: "Recordings stay local")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func measurementDetail(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(AppColors.accent)
                .frame(width: detailIconSize, height: detailIconSize)
                .background(AppColors.iconBackground, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppColors.heading)
                Text(detail).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func assetImage(_ name: String) -> Image {
        #if SWIFT_PACKAGE
        Image(name, bundle: .module)
        #else
        Image(name)
        #endif
    }
}

private struct AtrioSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    LabeledContent("Resting recording", value: "30 seconds")
                    Text("Rest your fingertip gently over the rear camera and flashlight. Their positions vary by iPhone. Choose other recording modes on the Preparation screen.")
                        .foregroundStyle(AppColors.secondaryText)
                    Button("Camera permissions") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section("Privacy") {
                    Text("Recordings stay on this iPhone. Nothing is automatically uploaded. Saved recordings are excluded from cloud backup; export them before deleting the app.")
                }
                Section("About Atrio") {
                    Text(ResearchNotice.detail).foregroundStyle(AppColors.secondaryText)
                }
            }
            .font(AppTypography.body)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(AppColors.accent)
    }
}

#Preview { AppRootView().preferredColorScheme(.light) }

struct HeartHealthView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Understand AFib")
                    .font(AppTypography.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Explore heart rhythm, medical evaluation, and when to seek help.")
                    .foregroundStyle(AppColors.secondaryText)
                StrokeEducationView()
                HeartEducationTopics()
                CareSearchView()
                ResearchDisclaimerView()
                Text("Sources: NIH / NHLBI and CDC. Reviewed October 21, 2026. General education, not personalized medical advice.")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.background.ignoresSafeArea())
        .foregroundStyle(AppColors.heading)
        .tint(AppColors.accent)
        .navigationTitle("Heart Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StrokeEducationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recognize a possible stroke", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("Sudden balance loss, vision changes, face drooping, arm weakness, or speech difficulty can signal a stroke. A sudden severe headache can also be a warning sign.")
            Text("Call 911 immediately in the U.S., even if symptoms go away. Elsewhere, call your local emergency number. Note when symptoms started. Do not drive yourself or wait for an app reading.")
                .fontWeight(.semibold)
            EducationSourceLink(title: "CDC: Stroke warning signs", address: "https://www.cdc.gov/stroke/signs-symptoms/")
        }
        .font(.callout)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HeartEducationTopics: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            EducationTopic(title: "What happens during AFib?",
                detail: "Atrial fibrillation is an irregular heart rhythm. The upper and lower heart chambers do not coordinate normally, and the heartbeat may become fast. Blood can pool and form clots, which can cause a stroke.",
                source: "https://www.nhlbi.nih.gov/health/atrial-fibrillation")
            EducationTopic(title: "Can AFib happen without symptoms?",
                detail: "Yes. Some people notice no symptoms. Others experience fatigue, fluttering or pounding heartbeats, dizziness, or breathlessness. Symptoms can come and go. Discuss new or recurring symptoms with a healthcare professional.",
                source: "https://www.nhlbi.nih.gov/health/atrial-fibrillation/symptoms")
            EducationTopic(title: "Why is an ECG important?",
                detail: "An ECG records the heart’s electrical activity. Clinicians use it alongside your history and examination to diagnose AFib; longer monitoring may be needed for intermittent episodes. Atrio measures optical pulse changes and cannot confirm or exclude AFib.",
                source: "https://www.nhlbi.nih.gov/health/atrial-fibrillation/diagnosis")
            EducationTopic(title: "How can treatment help?",
                detail: "A clinician may recommend medicines or procedures to manage heart rate and rhythm. Depending on individual stroke and bleeding risk, medicines that prevent clots may reduce stroke risk. Do not start or stop medication based on this app.",
                source: "https://www.nhlbi.nih.gov/health/atrial-fibrillation/treatment")
        }
    }
}

private struct EducationTopic: View {
    let title: String
    let detail: String
    let source: String

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(detail).foregroundStyle(AppColors.secondaryText)
                EducationSourceLink(title: "Read more at NIH / NHLBI", address: source)
            }
            .font(.callout)
            .padding(.top, 12)
        } label: {
            Text(title).font(.headline).frame(minHeight: 44, alignment: .leading)
        }
    }
}

private struct CareSearchView: View {
    @State private var location = ""

    private func searchURL(for service: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        components?.queryItems = [URLQueryItem(name: "q", value: place.isEmpty ? "\(service) near me" : "\(service) near \(place)")]
        return components?.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find care").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Search Apple Maps for a cardiologist or a clinic. Call ahead to confirm ECG services, appointments, and insurance. Search results are not verified by Atrio.")
                .font(.callout).foregroundStyle(AppColors.secondaryText)
            TextField("City or ZIP code (optional)", text: $location)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .accessibilityIdentifier("careSearchLocation")
            if let url = searchURL(for: "cardiologist") {
                Link(destination: url) {
                    Label("Find cardiologists in Maps", systemImage: "map")
                        .frame(minHeight: 44)
                }
            }
            if let url = searchURL(for: "ECG clinic") {
                Link(destination: url) {
                    Label("Find ECG clinics in Maps", systemImage: "cross.case")
                        .frame(minHeight: 44)
                }
            }
            Text("Maps uses your search area or its own location settings. No recording is sent. For a visit, open a saved measurement in History and choose Export PDF Report to share it yourself.")
                .font(.caption).foregroundStyle(AppColors.secondaryText)
        }
    }
}

private struct EducationSourceLink: View {
    let title: String
    let address: String

    var body: some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                Label(title, systemImage: "arrow.up.right.square")
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }
}
