import Foundation

/// UI text in the chosen language. English strings are the keys; anything missing falls back to English.
/// Views that show text observe `Prefs`, so switching language redraws them.
func tr(_ en: String) -> String {
    guard Prefs.shared.language == .tr else { return en }
    if let t = Strings.turkish[en] { return t }
    // Tuning names are built from a few words ("C♯ Standard", "Half Step Down (E♭)").
    var s = en
    for (a, b) in Strings.phrases where s.contains(a) { s = s.replacingOccurrences(of: a, with: b) }
    return s
}

/// `tr` with printf-style arguments: `trf("Degree %d", 3)`.
func trf(_ en: String, _ args: CVarArg...) -> String { String(format: tr(en), arguments: args) }

enum Strings {
    static let phrases: [(String, String)] = [
        ("Half Step Down", "Yarım Ses Pes"), ("Whole Step Down", "Tam Ses Pes"), ("New Standard", "Yeni Standart"),
        ("Standard", "Standart"), ("Open", "Açık"), ("Minor", "Minör"), ("All Fourths", "Hep Dörtlü"),
        ("High G", "Tiz G"), ("Low G", "Pes G"), ("D Tuning", "D Akordu"), ("Orchestral", "Orkestra"),
        ("Fifths", "Beşliler"), ("5-String", "5 Telli"), ("Cross", "Çapraz"), ("Dead Man's", "Dead Man's"),
        ("Irish", "İrlanda"), ("Turkish", "Türk"), ("Arabic", "Arap"), ("High C", "Tiz C"),
    ]

    static let turkish: [String: String] = [
        // Tabs & menus
        "Tuner": "Akort", "Chords": "Akorlar", "Scales": "Diziler", "Metronome": "Metronom",
        "Every bar": "Her ölçüde", "Every half bar": "Her yarım ölçüde", "Click · %d BPM": "Metronom · %d BPM",
        
        "Sing (Space)": "Söyle (Boşluk)", "Listening — sing a melody": "Dinliyor — bir melodi söyle",
        "Press and sing": "Bas ve söyle", "Done": "Bitti", "Play the chords": "Akorları çal",
        "Simple": "Basit", "Full": "Tam", "Rich": "Zengin", "every chord in the key": "tondaki tüm akorlar", "with 7ths, 9ths and 6ths": "7'li, 9'lu ve 6'lı akorlarla",
        "Melody": "Melodi", "Play your melody on the chosen instrument (M)": "Melodini seçili enstrümanla çal (M)",
        "Sing with the metronome: a one-bar count-in, and its tempo sets the bars": "Metronomla söyle: bir ölçü sayım, ölçüleri temposu belirler",
        "Get ready…": "Hazırlan…", "Found from your singing": "Şarkından bulunan", "Transpose": "Transpoze",
        "Loop it": "Döngüye al", "Loop these chords in Progressions with a rhythm and drums": "Bu akorları Progresyon'da ritim ve davulla döngüde çal",
        "Copy the chord chart": "Akor tablosunu kopyala", "Save melody and chords as a MIDI file; its tempo follows your singing": "Melodiyi ve akorları MIDI dosyası olarak kaydet; temposu senin söyleyişini izler",
        "Guitar: capo %d, then play %@": "Gitar: kapo %d, sonra şunları çal: %@",
        "Your recorded voice sits out while the chords are transposed.": "Akorlar transpoze edilirken kaydedilen sesin susar.", "My voice": "Sesim",
        "Play your recorded voice with the chords (V)": "Kaydedilen sesini akorlarla birlikte çal (V)", "Clear": "Temizle",
        "Hum or sing a few bars; chords appear as you go.": "Birkaç ölçü söyle ya da mırıldan; akorlar sen söyledikçe çıkar.",
        "Key: —": "Ton: —", "Key: %@": "Ton: %@", "Use this chord instead": "Bunun yerine bu akoru kullan",
        // EarQuiz
        "Scales & Makams": "Diziler ve Makamlar", "Which interval?": "Hangi aralık?", "Which chord?": "Hangi akor?",
        "Which scale?": "Hangi dizi?", "Which note?": "Hangi nota?", "Minor 2nd": "Küçük 2'li", "Major 2nd": "Büyük 2'li",
        "Mixed": "Karışık", "What do you hear?": "Ne duyuyorsun?", "Compound": "Bileşik", "Extended": "Genişletilmiş",
        "Common": "Yaygın", "Popular": "Popüler",
        "Minor 9th": "Küçük 9'lu", "Major 9th": "Büyük 9'lu", "Minor 10th": "Küçük 10'lu", "Major 10th": "Büyük 10'lu",
        "Perfect 11th": "Tam 11'li", "Augmented 11th": "Artık 11'li", "Perfect 12th": "Tam 12'li",
        "Intervals, chords, scales and notes, all mixed, from each kind's set.": "Aralık, akor, dizi ve nota karışık gelir; her türün kendi setinden.",
        "Minor 3rd": "Küçük 3'lü", "Major 3rd": "Büyük 3'lü", "Perfect 4th": "Tam 4'lü", "Perfect 5th": "Tam 5'li",
        "Minor 6th": "Küçük 6'lı", "Major 6th": "Büyük 6'lı", "Minor 7th": "Küçük 7'li", "Major 7th": "Büyük 7'li",
        "Octave": "Oktav", "Major": "Majör", "Minor": "Minör", "Beginner": "Başlangıç", "Intermediate": "Orta", "All": "Tümü",
        "Triads": "Üçlü akorlar", "Sevenths": "7'liler", "Makams": "Makamlar", "White keys": "Beyaz tuşlar",
        "Up": "Çıkıcı", "Down": "İnici", "Together": "Birlikte", "Broken": "Arpej", "Hear %@ first": "Önce %@ çal",
        "Custom": "Özel", "Choose which answers are in play": "Hangi cevapların sorulacağını seç", "Instrument": "Çalgı",
        "Play the question again (Space)": "Soruyu yeniden çal (Boşluk)", "Next": "Sonraki",
        "Next question (Return)": "Sonraki soru (Return)", "Choose what to practise": "Neye çalışacağını seç",
        "Click answers to include or leave them out.": "Eklemek ya da çıkarmak için cevaplara tıkla.",
        "%@ sounds almost the same": "%@ neredeyse aynı duyulur", "Not %@": "%@ değil",
        "Next one in a moment.": "Sıradaki birazdan.", "Click any answer to hear it.": "Duymak için bir cevaba tıkla.",
        "Press Space or ▶ to hear the first one.": "İlk soruyu duymak için Boşluk'a ya da ▶'ye bas.",
        "Space plays it again · number keys answer": "Boşluk yeniden çalar · rakam tuşları cevaplar",
        "streak": "seri", "best": "en iyi", "%d of %d": "%d / %d", "Practise more:": "Daha çok çalış:",
        "Missed most often; these come up more": "En sık kaçanlar; bunlar daha sık sorulur",
        "Next question automatically": "Sonraki soruya kendiliğinden geç", "after a right answer": "doğru cevaptan sonra",
        "New session": "Yeni oturum", "Forget scores": "Skorları sıfırla", "Right %d%% of the time": "%d%% doğru",
        "Other keys": "Diğer tonlar", "Pick another key if this one sounds off": "Bu ton yanlış geliyorsa başka birini seç",
        "Chord changes": "Akor değişimi", "How often the chord changes, and which chords to use": "Akor ne sıklıkla değişsin, hangi akorlar kullanılsın",
        "Pickup": "Anakruz", "none": "yok", "%d beat": "%d vuruş", "pickup": "anakruz", "Half time": "Yarım tempo", "Double time": "Çift tempo",
        "For songs that start before the first bar: move bar 1 to the first strong beat": "İlk ölçüden önce başlayan şarkılar için: 1. ölçüyü ilk güçlü vuruşa taşı",
        "Found from your singing; the bars follow you where you slow down or rush": "Şarkından bulundu; yavaşladığın ya da hızlandığın yerde ölçüler seni izler",
        "Chorden": "Chorden", "Edit": "Düzen", "View": "Görünüm", "Window": "Pencere",
        "About Chorden": "Chorden Hakkında", "Settings…": "Ayarlar…", "Hide Chorden": "Chorden'ı Gizle",
        "Hide Others": "Diğerlerini Gizle", "Show All": "Tümünü Göster", "Quit Chorden": "Chorden'dan Çık",
        "Undo": "Geri Al", "Redo": "Yinele", "Cut": "Kes", "Copy": "Kopyala", "Paste": "Yapıştır",
        "Select All": "Tümünü Seç", "Find Chord…": "Akor Bul…", "Reference Tone": "Referans Ton",
        "Start/Stop Metronome": "Metronomu Başlat/Durdur", "Minimize": "Küçült", "Close": "Kapat",
        "Open Chorden": "Chorden'ı Aç", "Settings (⌘,)": "Ayarlar (⌘,)",

        // Settings
        "Language": "Dil", "Guitar sound": "Gitar sesi", "Auto": "Otomatik", "Acoustic": "Akustik",
        "Classical": "Klasik", "Electric": "Elektro", "follows the instrument": "enstrümana göre",
        "steel strings": "çelik tel", "nylon strings": "naylon tel", "clean amp": "temiz amfi", "Appearance": "Görünüm", "System": "Sistem", "Light": "Açık", "Dark": "Koyu",
        "Light mode": "Açık mod", "Dark mode": "Koyu mod", "Reference": "Referans", "In tune within": "Akort toleransı", "Note names": "Nota adları",
        "Input": "Giriş", "Channel": "Kanal", "Noise gate": "Gürültü kapısı", "Open at login": "Girişte aç",
        "System Default": "Sistem Varsayılanı", "Loudest": "En güçlü", "Input %d": "Giriş %d",
        "Double-click to reset to 440 Hz": "440 Hz'e dönmek için çift tıkla",

        // Instruments
        "Chromatic": "Kromatik", "Makam": "Makam", "any note": "her nota", "53-koma degrees": "53 komalık perdeler",
        "Guitar": "Gitar", "7-String Guitar": "7 Telli Gitar", "8-String Guitar": "8 Telli Gitar",
        "Bass": "Bas Gitar", "5-String Bass": "5 Telli Bas", "6-String Bass": "6 Telli Bas",
        "Violin": "Keman", "Viola": "Viyola", "Cello": "Çello", "Double Bass": "Kontrbas",
        "Baritone Ukulele": "Bariton Ukulele", "Irish Bouzouki": "İrlanda Buzukisi", "Balalaika": "Balalayka",
        "Oud": "Ud", "Greek Bouzouki": "Yunan Buzukisi",
        "Bowed": "Yaylılar", "Folk": "Halk Çalgıları", "Turkish & Middle Eastern": "Türk ve Orta Doğu",
        "Drop": "Drop", "Other": "Diğer", "Favorites": "Favoriler", "My Tunings": "Akortlarım",
        "Custom tuning": "Kendi akordun", "New tuning": "Yeni akort", "Edit tuning": "Akordu düzenle",
        "Name": "Ad", "Save": "Kaydet", "Delete": "Sil", "Karar": "Karar", "Karar %@": "Karar %@",

        // Tuner
        "One string": "Tek tel", "All strings": "Tüm teller", "Intonation": "Entonasyon",
        "Needle": "İbre", "Strobe": "Strobe", "Trace": "İz",
        "Play a string": "Bir tel çal", "Play a note": "Bir nota çal", "In tune": "Akortlu",
        "Tune up": "Gerdir", "Tune down": "Gevşet", "hearing %@": "duyulan %@",
        "Degree %d": "%d. derece", "click to lock": "kilitlemek için tıkla", "click to unlock": "kilidi açmak için tıkla",
        "Reference tone (Space)": "Referans ton (Boşluk)", "Listening": "Dinliyor", "Microphone off": "Mikrofon kapalı",
        "Deviation in komas (1 koma = 22.6 cents)": "Koma cinsinden sapma (1 koma = 22,6 cent)",
        "Chorden needs microphone access to hear your instrument.": "Chorden'ın enstrümanını duyabilmesi için mikrofon izni gerekiyor.",
        "Open Privacy Settings": "Gizlilik Ayarlarını Aç", "Try Again": "Tekrar Dene",
        "Strum all strings": "Tüm tellere birden vur", "All strings in tune": "Tüm teller akortlu",
        "Tune the strings that are off, then strum again": "Kaçık telleri düzelt, sonra tekrar vur",
        "Play the open %@ string": "Açık %@ telini çal", "Now the 12th fret on %@": "Şimdi %@ telinde 12. perde",
        "%@ string": "%@ teli",
        "Tune the string first. Let it ring steadily; Chorden measures it exactly.":
            "Önce teli akortla. Sabit tınlamasına izin ver; Chorden tam olarak ölçer.",
        "Fret the 12th fret with normal pressure and let it ring.": "12. perdeye normal kuvvetle bas ve tınlamasına izin ver.",
        "Compared with a perfect octave of the open string.": "Açık telin tam oktavıyla karşılaştırıldı.",
        "Intonation is good": "Entonasyon iyi",
        "Sharp: move the saddle back, away from the neck": "Tiz: eşiği geriye, saptan uzağa al",
        "Flat: move the saddle forward, toward the neck": "Pes: eşiği ileriye, sapa doğru al",
        "Measure again": "Tekrar ölç", "Next string": "Sonraki tel",

        // Chords
        "Library": "Kütüphane", "Listen": "Dinle", "Listening…": "Dinliyor…",
        "Play a chord and Chorden names it": "Bir akor çal, Chorden adını söylesin", "Random chord": "Rastgele akor",
        "Find chord  e.g. F♯m7": "Akor bul  örn. F♯m7", "Favorite": "Favori",
        "Shapes": "Şekiller", "Neck": "Sap", "Fingers": "Parmaklar", "Notes": "Notalar", "Intervals": "Aralıklar",
        "Chord tones on the fingerboard": "Klavye üzerinde akor notaları",
        "No playable shape in this tuning.": "Bu akortta çalınabilir şekil yok.",
        "Click to play": "Çalmak için tıkla",
        "Click to play · double-click to open in the library": "Çalmak için tıkla · kütüphanede açmak için çift tıkla",
        "Microtonal: nearest fret shown": "Mikrotonal: en yakın perde gösteriliyor",
        "%d chords": "%d akor", "Progressions": "Progresyon", "Play / stop the loop (Space)": "Döngüyü çal / durdur (Boşluk)",
        "Tempo": "Tempo", "Chord length": "Akor süresi", "Number of chords": "Akor sayısı", "Change chord": "Akoru değiştir", "Remove chord": "Akoru kaldır", "Add a chord": "Akor ekle", "Any chord": "Herhangi bir akor","½ bar": "½ ölçü", "1 bar": "1 ölçü", "2 bars": "2 ölçü",
        "My progressions": "Progresyonlarım", "My takes": "Kayıtlarım", "Saved": "Kaydedildi", "Rename": "Yeniden adlandır", "Click again to delete": "Silmek için tekrar tıkla", "Open a saved progression": "Kaydedilmiş bir progresyonu aç", "Open a saved take": "Kaydedilmiş bir kaydı aç", "Save this progression with its tempo and rhythm": "Bu progresyonu temposu ve ritmiyle kaydet", "Keep this take with your voice and chosen chords; reopen it from My takes": "Bu kaydı sesin ve seçtiğin akorlarla sakla; Kayıtlarım'dan yeniden aç",
        "Rhythm": "Ritim", "Drums": "Davul", "Swing": "Swing", "Loop": "Döngü",
        "Whole": "Uzun", "Quarters": "Dörtlük", "Down-up": "Aşağı-yukarı", "Folk strum": "Folk", "Fingerpicking": "Parmak (arpej)",
        "Rock 8ths": "Rock sekizlik", "Off": "Kapalı", "Click": "Klik", "Groove": "Groove", "Ballad": "Balad",
        "Pop 16ths": "Pop on altılık", "Shuffle": "Shuffle", "Reggae skank": "Reggae skank", "Funk scratch": "Funk scratch",
        "Palm-mute chug": "Palm mute", "Gallop": "Dörtnala (gallop)", "Travis picking": "Travis picking",
        "Bossa nova": "Bossa nova", "Rock beat": "Rock", "Four on the floor": "Four on the floor (disko)",
        "Funk beat": "Funk", "Blues shuffle": "Blues shuffle", "Jazz swing": "Caz swing", "Bossa groove": "Bossa",
        "One drop": "One drop (reggae)", "Boom bap": "Boom bap (hip-hop)", "Half-time": "Yarım tempo", "Any mood": "Her tarz", "major": "majör", "minor": "minör",
        "Play": "Çal", "Stop": "Durdur", "New": "Yeni", "New progression": "Yeni dizi",
        "Happy": "Neşeli", "Melancholic": "Melankolik", "Epic": "Epik", "Dreamy": "Rüya gibi", "Jazz": "Caz",
        "Rock": "Rock", "Oriental": "Oryantal",
        "Uplifting": "Umut dolu", "Romantic": "Romantik", "Gloomy": "Karanlık", "Cinematic": "Sinematik",
        "Lo-fi": "Lo-fi", "Bossa": "Bossa nova", "Soul": "Soul", "Gospel": "Gospel", "Country": "Country",
        "Reggae": "Reggae", "Anime": "Anime", "Arabesk": "Arabesk",
        "power chord": "power akor", "dominant 7th": "dominant 7'li", "major 7th": "majör 7'li", "minor 7th": "minör 7'li",
        "suspended 2nd": "sus 2", "suspended 4th": "sus 4", "7th suspended 4th": "7'li sus 4",
        "added 9th": "eklenmiş 9'lu", "minor added 9th": "minör eklenmiş 9'lu", "major 6th": "majör 6'lı",
        "minor 6th": "minör 6'lı", "six-nine": "altı-dokuz", "dominant 9th": "dominant 9'lu", "major 9th": "majör 9'lu",
        "minor 9th": "minör 9'lu", "dominant 11th": "dominant 11'li", "minor 11th": "minör 11'li",
        "dominant 13th": "dominant 13'lü", "diminished": "eksik", "diminished 7th": "eksik 7'li",
        "half-diminished": "yarım eksik", "augmented": "artık", "augmented 7th": "artık 7'li",
        "dominant 7th ♭9": "dominant 7 ♭9", "dominant 7th ♯9": "dominant 7 ♯9", "minor major 7th": "minör majör 7'li",

        // Scales
        "Modes": "Modlar", "Pentatonic & Blues": "Pentatonik ve Blues", "Minor & Exotic": "Minör ve Egzotik",
        "Symmetric": "Simetrik", "Major (Ionian)": "Majör (İyonyen)", "Dorian": "Doryen", "Phrygian": "Frigyen",
        "Lydian": "Lidyen", "Mixolydian": "Miksolidyen", "Minor (Aeolian)": "Minör (Eolyen)", "Locrian": "Lokriyen",
        "Major Pentatonic": "Majör Pentatonik", "Minor Pentatonic": "Minör Pentatonik", "Major Blues": "Majör Blues",
        "Harmonic Minor": "Armonik Minör", "Melodic Minor": "Melodik Minör", "Phrygian Dominant": "Frigyen Dominant",
        "Hungarian Minor": "Macar Minör", "Double Harmonic": "Çift Armonik", "Whole Tone": "Tam Ton",
        "Diminished (H–W)": "Eksik (Y–T)", "Diminished (W–H)": "Eksik (T–Y)",
        "Whole neck": "Tüm sap", "Asian": "Asya", "Indian": "Hint", "Arabic Maqam": "Arap Makamı",
        "Bebop Minor": "Bebop Minör", "Bebop Melodic Minor": "Bebop Melodik Minör", "Lydian ♯2": "Lidyen ♯2",
        "Ionian ♯5": "İyonyen ♯5", "Locrian ♮6": "Lokriyen ♮6", "Ultralocrian": "Ultralokriyen",
        "Dominant Pentatonic": "Dominant Pentatonik", "Man Gong (Chinese)": "Man Gong (Çin)",
        "Slendro (5-equal)": "Slendro (5 eşit)", "Harmonic Major": "Armonik Majör", "Spanish 8-tone": "İspanyol 8 tonlu",
        "Tritone": "Triton", "Rast (Arabic)": "Rast (Arap)", "Saba (Arabic)": "Saba (Arap)",
        "Keyboard": "Klavye", "Piano": "Piyano", "Equal temperament": "Eşit akort",
        "Root position": "Kök durum", "1st inversion": "1. çevrim", "2nd inversion": "2. çevrim", "3rd inversion": "3. çevrim",
        "Open voicing": "Açık diziliş", "Inversions and voicings · click a keyboard to hear it": "Çevrimler ve dizilişler · dinlemek için klavyeye tıkla",
        "A piano can't play these microtones: dashed keys are the nearest note. ▶ plays the true pitches.":
            "Piyano bu mikrotonları çalamaz: kesikli tuşlar en yakın notadır. ▶ gerçek perdeleri çalar.",
        "Lydian Dominant": "Lidyen Dominant", "Altered": "Altere", "Lydian Augmented": "Lidyen Artık",
        "Locrian ♮2": "Lokriyen ♮2", "Mixolydian ♭6": "Miksolidyen ♭6", "Dorian ♭2": "Doryen ♭2",
        "Bebop Dominant": "Bebop Dominant", "Bebop Major": "Bebop Majör", "Egyptian (Suspended)": "Mısır (Asma)",
        "Pelog (approx.)": "Pelog (yaklaşık)", "Neapolitan Minor": "Napoliten Minör", "Neapolitan Major": "Napoliten Majör",
        "Ukrainian Dorian": "Ukrayna Doryen", "Hungarian Major": "Macar Majör", "Persian": "Fars", "Enigmatic": "Enigmatik",
        "Prometheus": "Prometheus", "Augmented": "Artık", "Degrees": "Dereceler", "koma": "koma",
        "Koma degrees drawn at their exact place": "Koma perdeleri tam yerinde çiziliyor",
        "Dashed dots are microtones between frets: bend or slide slightly to reach them.":
            "Kesikli noktalar perdeler arasındaki mikrotonlardır: ulaşmak için hafifçe bend ya da kaydırma yap.",

        // Metronome
        "Tap": "Vur", "Click sound": "Tık sesi",
        "Classic": "Klasik", "Woodblock": "Tahta blok", "Beep": "Elektronik bip", "Cowbell": "İnek çanı", "Hi-hat": "Hi-hat",
        "mechanical tick, bell on one": "mekanik tık, ilk vuruşta zil", "warm and woody": "sıcak, tahta tınısı",
        "clean electronic tone": "temiz elektronik ses", "cuts through a band": "grubun içinde duyulur",
        "soft, drummer-friendly": "yumuşak, davulcu dostu", "Start / stop (Space)": "Başlat / durdur (Boşluk)", "Tap the tempo (T)": "Tempoyu vur (T)",
        "Drag up or down, or use ↑ ↓": "Yukarı/aşağı sürükle ya da ↑ ↓ kullan",
        "Quarter notes": "Dörtlükler", "Eighth notes": "Sekizlikler", "Triplets": "Trioleler", "Sixteenth notes": "On altılıklar",
    ]
}
