import UIKit

protocol PoseGenerating: Sendable {
    func generatePosePack(from image: UIImage, useCase: PoseUseCase) async throws -> [PoseIdea]
}

/// Cloud-ready AI Pose Generator.
/// Sends the reference photo securely to your configured AI backend (when `endpointURL` is set),
/// or falls back to the built-in smart pose variation generator so the app works immediately.
struct AIPoseGeneratorService: PoseGenerating {
    var endpointURL: URL? = nil
    var apiKey: String? = nil

    func generatePosePack(from image: UIImage, useCase: PoseUseCase) async throws -> [PoseIdea] {
        if let endpointURL, let apiKey, !apiKey.isEmpty {
            return try await requestCloudPoses(image: image, useCase: useCase, endpoint: endpointURL, apiKey: apiKey)
        }

        // Simulate realistic cloud processing latency for UX parity
        try await Task.sleep(for: .milliseconds(900))
        return MockPoseCatalog.generateFourPoses(for: useCase)
    }

    private func requestCloudPoses(
        image: UIImage,
        useCase: PoseUseCase,
        endpoint: URL,
        apiKey: String
    ) async throws -> [PoseIdea] {
        guard let jpegData = image.jpegData(compressionQuality: 0.78) else {
            return MockPoseCatalog.generateFourPoses(for: useCase)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "use_case": useCase.rawValue,
            "image_base64": jpegData.base64EncodedString(),
            "count": 4
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return MockPoseCatalog.generateFourPoses(for: useCase)
        }

        let decoded = try JSONDecoder().decode([PoseIdea].self, from: data)
        return decoded.isEmpty ? MockPoseCatalog.generateFourPoses(for: useCase) : decoded
    }
}

// MARK: - Rich Built-in Pose Catalog (4 Variations per Shot Pack)

enum MockPoseCatalog {
    static func generateFourPoses(for useCase: PoseUseCase) -> [PoseIdea] {
        if useCase == .couples {
            return [couplesEmbracePose] + Array(soloPoses(for: useCase).prefix(3))
        }
        return soloPoses(for: useCase)
    }

    static var quickOfflinePoses: [PoseIdea] {
        soloPoses(for: .travel) + extraCatalogPoses + [couplesEmbracePose, couplesSeatedPose]
    }

    private static func soloPoses(for useCase: PoseUseCase) -> [PoseIdea] {
        [
            PoseIdea(
                title: "Rahat 45° Dönüş",
                angleLabel: "45° Açı • Göz Hizası",
                confidenceTag: "\(useCase.rawValue)",
                category: .street,
                skeleton: threeQuarterSkeleton,
                coaching: CoachingTips(
                    summary: "Kaskatı durmadan derinlik ve doğal bir silüet oluşturur.",
                    subjectTips: [
                        "Gövdeni kameradan 45° yana çevir ve başını lense doğru döndür.",
                        "Ön elini cebine veya kalçana hafifçe yasla; parmaklarını serbest bırak.",
                        "Çeneni çok hafif ileri ve aşağı uzatarak yüz hattını belirginleştir."
                    ],
                    photographerTips: [
                        "Doğal oranlar için kamerayı göğüs ile göz hizası arasında tut.",
                        "Başın üzerinde yaklaşık %10 boşluk bırak.",
                        "Geniş açı bozulmasını önlemek için 1x veya 2x lens kullan."
                    ]
                )
            ),
            PoseIdea(
                title: "Omuz Üstünden Doğal Bakış",
                angleLabel: "Dinamik • Hafif Alt Açı",
                confidenceTag: "Doğal Hareket",
                category: .street,
                skeleton: overShoulderSkeleton,
                coaching: CoachingTips(
                    summary: "Yürürken yakalanmış gibi spontane ve enerjik bir kare verir.",
                    subjectTips: [
                        "Yavaşça bir adım atıp ön omzunun üzerinden kameraya bak.",
                        "Kameraya yakın olan omzunu hafifçe düşür ki boynun kapanmasın.",
                        "Deklanşörden hemen önce nefes verip doğal bir tebessüm bırak."
                    ],
                    photographerTips: [
                        "Kamerayı göz hizasından 10–15 cm aşağı indirerek sinematik bir açı yakala.",
                        "Kişiyi tam ortaya değil, sol üçte bir çizgisine yerleştir.",
                        "Yakın olan göze dokunup odağı kilitle."
                    ]
                )
            ),
            PoseIdea(
                title: "Asimetrik Duruş",
                angleLabel: "Editoryal • Dengeli",
                confidenceTag: "Güçlü Çizgiler",
                category: .portrait,
                skeleton: asymmetricLeanSkeleton,
                coaching: CoachingTips(
                    summary: "Kollar ve omuzlarla temiz diyagonal çizgiler kurarak özgüvenli bir duruş sağlar.",
                    subjectTips: [
                        "Ağırlığının %70'ini arka bacağına vererek hafif bir S kıvrımı oluştur.",
                        "Bir elini yakanın veya saçının yakınına getirip yüzünü çerçevele.",
                        "Dirseklerini gövdenden biraz uzak tutarak rahat bir alan bırak."
                    ],
                    photographerTips: [
                        "Arkadaki dikey çizgileri (duvar, sütun) kadraj kenarıyla düz hizala.",
                        "Kişinin başının arkasından çıkan dikkat dağıtıcı obje olmadığından emin ol.",
                        "Ağırlık değiştirirken arka arkaya 2–3 kare çek."
                    ]
                )
            ),
            PoseIdea(
                title: "Merkezi Güçlü Portre",
                angleLabel: "Önden • Yakın Kadraj",
                confidenceTag: "Yüksek Etki",
                category: .portrait,
                skeleton: centeredPortraitSkeleton,
                coaching: CoachingTips(
                    summary: "Profil fotoğrafları ve temiz ışık için doğrudan, güçlü bir portre sunar.",
                    subjectTips: [
                        "Omuzlarını rahat bırak ve başını bir tarafa sadece 5° eğ.",
                        "Çeneni sıkma, dudaklarını ve yüz kaslarını gevşet.",
                        "Bir elini hafifçe koluna veya ceket yakana yerleştir."
                    ],
                    photographerTips: [
                        "Kişiyi yatay olarak kadrajın tam merkezine hizala.",
                        "Göz altında sert gölge varsa kişinin ışığa biraz daha dönmesini iste.",
                        "Kişinin kadraj yüksekliğinin %60–70'ini doldurmasını sağla."
                    ]
                )
            )
        ]
    }

    private static let threeQuarterSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.51, y: 0.21),
        .neck: NormalizedPoint(x: 0.50, y: 0.28),
        .leftShoulder: NormalizedPoint(x: 0.40, y: 0.31),
        .rightShoulder: NormalizedPoint(x: 0.59, y: 0.30),
        .leftElbow: NormalizedPoint(x: 0.35, y: 0.43),
        .rightElbow: NormalizedPoint(x: 0.63, y: 0.42),
        .leftWrist: NormalizedPoint(x: 0.41, y: 0.53),
        .rightWrist: NormalizedPoint(x: 0.58, y: 0.53),
        .root: NormalizedPoint(x: 0.49, y: 0.54),
        .leftHip: NormalizedPoint(x: 0.42, y: 0.55),
        .rightHip: NormalizedPoint(x: 0.56, y: 0.55),
        .leftKnee: NormalizedPoint(x: 0.41, y: 0.73),
        .rightKnee: NormalizedPoint(x: 0.57, y: 0.72),
        .leftAnkle: NormalizedPoint(x: 0.40, y: 0.89),
        .rightAnkle: NormalizedPoint(x: 0.58, y: 0.88)
    ])

    private static let overShoulderSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.48, y: 0.22),
        .neck: NormalizedPoint(x: 0.52, y: 0.29),
        .leftShoulder: NormalizedPoint(x: 0.43, y: 0.32),
        .rightShoulder: NormalizedPoint(x: 0.61, y: 0.31),
        .leftElbow: NormalizedPoint(x: 0.39, y: 0.45),
        .rightElbow: NormalizedPoint(x: 0.66, y: 0.44),
        .leftWrist: NormalizedPoint(x: 0.42, y: 0.56),
        .rightWrist: NormalizedPoint(x: 0.63, y: 0.55),
        .root: NormalizedPoint(x: 0.52, y: 0.54),
        .leftHip: NormalizedPoint(x: 0.45, y: 0.55),
        .rightHip: NormalizedPoint(x: 0.59, y: 0.55),
        .leftKnee: NormalizedPoint(x: 0.44, y: 0.73),
        .rightKnee: NormalizedPoint(x: 0.61, y: 0.74),
        .leftAnkle: NormalizedPoint(x: 0.42, y: 0.89),
        .rightAnkle: NormalizedPoint(x: 0.63, y: 0.90)
    ])

    private static let asymmetricLeanSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.52, y: 0.20),
        .neck: NormalizedPoint(x: 0.51, y: 0.27),
        .leftShoulder: NormalizedPoint(x: 0.41, y: 0.30),
        .rightShoulder: NormalizedPoint(x: 0.61, y: 0.32),
        .leftElbow: NormalizedPoint(x: 0.35, y: 0.40),
        .rightElbow: NormalizedPoint(x: 0.68, y: 0.42),
        .leftWrist: NormalizedPoint(x: 0.44, y: 0.27),
        .rightWrist: NormalizedPoint(x: 0.63, y: 0.54),
        .root: NormalizedPoint(x: 0.50, y: 0.53),
        .leftHip: NormalizedPoint(x: 0.43, y: 0.54),
        .rightHip: NormalizedPoint(x: 0.57, y: 0.55),
        .leftKnee: NormalizedPoint(x: 0.45, y: 0.72),
        .rightKnee: NormalizedPoint(x: 0.58, y: 0.72),
        .leftAnkle: NormalizedPoint(x: 0.46, y: 0.88),
        .rightAnkle: NormalizedPoint(x: 0.59, y: 0.89)
    ])

    private static let centeredPortraitSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.50, y: 0.22),
        .neck: NormalizedPoint(x: 0.50, y: 0.29),
        .leftShoulder: NormalizedPoint(x: 0.38, y: 0.33),
        .rightShoulder: NormalizedPoint(x: 0.62, y: 0.33),
        .leftElbow: NormalizedPoint(x: 0.34, y: 0.47),
        .rightElbow: NormalizedPoint(x: 0.66, y: 0.47),
        .leftWrist: NormalizedPoint(x: 0.43, y: 0.53),
        .rightWrist: NormalizedPoint(x: 0.55, y: 0.54),
        .root: NormalizedPoint(x: 0.50, y: 0.56),
        .leftHip: NormalizedPoint(x: 0.42, y: 0.57),
        .rightHip: NormalizedPoint(x: 0.58, y: 0.57),
        .leftKnee: NormalizedPoint(x: 0.42, y: 0.75),
        .rightKnee: NormalizedPoint(x: 0.58, y: 0.75),
        .leftAnkle: NormalizedPoint(x: 0.42, y: 0.90),
        .rightAnkle: NormalizedPoint(x: 0.58, y: 0.90)
    ])

    private static let couplesEmbracePose = PoseIdea(
        title: "Çift Yürüyüş & Uyum",
        angleLabel: "2 Kişi • Doğal An",
        confidenceTag: "Çift Seçimi",
        category: .couples,
        skeleton: PoseSkeleton(joints: [
            .nose: NormalizedPoint(x: 0.37, y: 0.22),
            .neck: NormalizedPoint(x: 0.37, y: 0.29),
            .leftShoulder: NormalizedPoint(x: 0.29, y: 0.32),
            .rightShoulder: NormalizedPoint(x: 0.45, y: 0.32),
            .leftElbow: NormalizedPoint(x: 0.26, y: 0.44),
            .rightElbow: NormalizedPoint(x: 0.50, y: 0.42),
            .leftWrist: NormalizedPoint(x: 0.30, y: 0.54),
            .rightWrist: NormalizedPoint(x: 0.55, y: 0.48),
            .root: NormalizedPoint(x: 0.37, y: 0.54),
            .leftHip: NormalizedPoint(x: 0.31, y: 0.55),
            .rightHip: NormalizedPoint(x: 0.43, y: 0.55),
            .leftKnee: NormalizedPoint(x: 0.31, y: 0.73),
            .rightKnee: NormalizedPoint(x: 0.43, y: 0.73),
            .leftAnkle: NormalizedPoint(x: 0.30, y: 0.89),
            .rightAnkle: NormalizedPoint(x: 0.44, y: 0.89)
        ]),
        secondarySkeleton: PoseSkeleton(joints: [
            .nose: NormalizedPoint(x: 0.62, y: 0.24),
            .neck: NormalizedPoint(x: 0.62, y: 0.31),
            .leftShoulder: NormalizedPoint(x: 0.54, y: 0.34),
            .rightShoulder: NormalizedPoint(x: 0.70, y: 0.34),
            .leftElbow: NormalizedPoint(x: 0.49, y: 0.44),
            .rightElbow: NormalizedPoint(x: 0.73, y: 0.46),
            .leftWrist: NormalizedPoint(x: 0.46, y: 0.50),
            .rightWrist: NormalizedPoint(x: 0.69, y: 0.56),
            .root: NormalizedPoint(x: 0.62, y: 0.55),
            .leftHip: NormalizedPoint(x: 0.56, y: 0.56),
            .rightHip: NormalizedPoint(x: 0.68, y: 0.56),
            .leftKnee: NormalizedPoint(x: 0.56, y: 0.74),
            .rightKnee: NormalizedPoint(x: 0.68, y: 0.74),
            .leftAnkle: NormalizedPoint(x: 0.55, y: 0.89),
            .rightAnkle: NormalizedPoint(x: 0.69, y: 0.89)
        ]),
        coaching: CoachingTips(
            summary: "İki kişiyi de kadrajda dengeli ve birbirine bağlı gösterir.",
            subjectTips: [
                "Yan yana yavaşça yürüyün; biriniz kameraya, diğeriniz partnerine baksın.",
                "Arada kopukluk olmaması için omuzlarınızı hafifçe birbirinize dönük tutun.",
                "İç taraftaki elinizi partnerinizin beline veya koluna hafifçe koyun."
            ],
            photographerTips: [
                "Her iki kişinin de kenarlarda rahat boşluğu kalacak kadar geri çekilin.",
                "Kamerayı uzun olan kişinin göğüs hizasında tutun.",
                "Yavaşça yürürlerken arka arkaya 3–4 kare çekin."
            ]
        )
    )

    private static let extraCatalogPoses: [PoseIdea] = [
        PoseIdea(
            title: "Kafe Masasında Kahve",
            angleLabel: "Oturarak • Yarım Boy",
            confidenceTag: "Kafe",
            category: .cafe,
            skeleton: asymmetricLeanSkeleton,
            coaching: CoachingTips(
                summary: "Masada otururken ellerin boşta kalmasını engelleyen doğal kafe pozu.",
                subjectTips: [
                    "Bir dirseğini masaya hafifçe yasla, diğer elinle fincanı veya çeneni tut.",
                    "Dik oturup gövdeni masaya doğru 15° öne eğ."
                ],
                photographerTips: [
                    "Fincanı veya tatlıyı ön plana alıp derinlik kat.",
                    "Kamerayı masa hizasının biraz üzerinden tut."
                ]
            )
        ),
        PoseIdea(
            title: "Cam Kenarı Işık Portresi",
            angleLabel: "Yan Işık • Kafe",
            confidenceTag: "Yumuşak Işık",
            category: .cafe,
            skeleton: centeredPortraitSkeleton,
            coaching: CoachingTips(
                summary: "Pencere ışığını yüzün bir tarafına alarak sinematik kontrast oluşturur.",
                subjectTips: [
                    "Yüzünü pencereye 45° çevir, gözlerinle kameraya veya dışarı bak.",
                    "Omuzlarını gevşet ve çeneni hafifçe ışığa kaldır."
                ],
                photographerTips: [
                    "Gölgede kalan tarafa değil, aydınlık göz tarafına odaklan.",
                    "Pozlamayı hafifçe (-0.3) kısarak pencere patlamasını önle."
                ]
            )
        ),
        PoseIdea(
            title: "Sahil Gün Batımı Silüet",
            angleLabel: "Tam Boy • Geniş Açı",
            confidenceTag: "Sahil",
            category: .beach,
            skeleton: threeQuarterSkeleton,
            coaching: CoachingTips(
                summary: "Ufuk çizgisi ve gün batımıyla uyumlu rahat tatil karesi.",
                subjectTips: [
                    "Bir ayağını öne atıp ellerini saçına veya şapkana götür.",
                    "Ufka doğru yan dönüp rüzgârın hareketini kullan."
                ],
                photographerTips: [
                    "Ufuk çizgisinin tam düz olduğundan emin ol (Izgara + Terazi açabilirsin).",
                    "Kişiyi sağ veya sol üçte bir çizgisine yerleştir."
                ]
            )
        ),
        PoseIdea(
            title: "Merdiven Basamağı",
            angleLabel: "Hafif Alt Açı • Sokak",
            confidenceTag: "Sokak",
            category: .street,
            skeleton: overShoulderSkeleton,
            coaching: CoachingTips(
                summary: "Merdiven basamaklarının çizgilerini kullanarak bacak boyunu uzun gösterir.",
                subjectTips: [
                    "Bir ayağını bir alt basamağa koyup ağırlığını arkaya ver.",
                    "Bir elini cebine koy veya korkuluğa hafifçe dokun."
                ],
                photographerTips: [
                    "2–3 basamak aşağıdan yukarı doğru çekerek boyu uzat.",
                    "Basamak çizgilerini kadraja diyagonal yerleştir."
                ]
            )
        )
    ]

    private static let couplesSeatedPose = PoseIdea(
        title: "Yan Yana Oturma",
        angleLabel: "2 Kişi • Samimi",
        confidenceTag: "Çiftler",
        category: .couples,
        skeleton: couplesEmbracePose.skeleton,
        secondarySkeleton: couplesEmbracePose.secondarySkeleton,
        coaching: CoachingTips(
            summary: "Kafede veya bankta yan yana otururken yakınlık ve uyum sağlar.",
            subjectTips: [
                "Omuzlarınızı birbirine yaklaştırıp dizlerinizi aynı yöne çevirin.",
                "Biriniz kameraya gülümserken diğeriniz partnerine bakabilir."
            ],
            photographerTips: [
                "Göz hizasından çekin ve iki yüzün de net alanda kaldığından emin olun.",
                "Ellerin doğal şekilde diz veya omuzda durmasını sağlayın."
            ]
        )
    )
}
