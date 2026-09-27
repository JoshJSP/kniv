import SwiftUI

/// Scoreblok voor een spelletjesavond: spelers, rondes, wie er voor staat. Blijft bewaard tot je een nieuw spel begint.
struct ScoreblokView: View {
    struct Spel: Codable, Equatable {
        var spelers: [String] = []
        var rondes: [[Int]] = []
        var laagsteWint = false
        var doel: Int?
    }

    @AppStorage("scoreblok") private var opgeslagen = ""
    @State private var spel = Spel()
    @State private var nieuweSpeler = ""
    @State private var invoer: [String] = []
    @State private var toonNieuw = false
    @FocusState private var veld: Int?

    private var totalen: [Int] { Scores.totalen(spel.rondes, spelers: spel.spelers.count) }
    private var stand: [Int] { Scores.stand(totalen, laagsteWint: spel.laagsteWint) }
    private var winnaar: Int? {
        guard let doel = spel.doel, let eerste = stand.first, !spel.rondes.isEmpty else { return nil }
        return totalen.contains { $0 >= doel } ? eerste : nil
    }

    var body: some View {
        List {
            if let w = winnaar {
                Section {
                    Label("\(spel.spelers[w]) wint!", systemImage: "crown.fill")
                        .font(.title2.bold()).foregroundStyle(Color.accentColor)
                }
            }
            Section {
                ForEach(Array(stand.enumerated()), id: \.element) { paar in
                    let (plek, i) = (paar.offset, paar.element)
                    HStack {
                        Text(verbatim: "\(plek + 1).").foregroundStyle(.secondary).monospacedDigit().frame(width: 28, alignment: .leading)
                        Text(verbatim: spel.spelers[i]).font(.headline)
                        if plek == 0 && !spel.rondes.isEmpty { Image(systemName: "crown.fill").foregroundStyle(.yellow) }
                        Spacer()
                        Text(verbatim: "\(totalen[i])").font(.title3.weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .onDelete { weg in
                    for i in weg.map({ stand[$0] }).sorted(by: >) {
                        spel.spelers.remove(at: i)
                        for r in spel.rondes.indices where i < spel.rondes[r].count { spel.rondes[r].remove(at: i) }
                    }
                }
                HStack {
                    TextField("Speler toevoegen", text: $nieuweSpeler).onSubmit(voegToe)
                    Button("Voeg toe", action: voegToe).disabled(nieuweSpeler.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text(spel.rondes.isEmpty ? "Spelers" : "Stand na \(spel.rondes.count) rondes")
            }

            if !spel.spelers.isEmpty {
                Section("Nieuwe ronde") {
                    ForEach(spel.spelers.indices, id: \.self) { i in
                        HStack {
                            Text(verbatim: spel.spelers[i])
                            Spacer()
                            TextField("0", text: binding(i))
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .focused($veld, equals: i)
                                .onSubmit { veld = i + 1 < spel.spelers.count ? i + 1 : nil }
                        }
                    }
                    Button {
                        spel.rondes.append(spel.spelers.indices.map { Int(invoer[safe: $0] ?? "") ?? 0 })
                        invoer = []
                        veld = nil
                    } label: {
                        Label("Ronde opslaan", systemImage: "plus.circle.fill")
                    }
                    .disabled(invoer.allSatisfy { Int($0) == nil })
                }
            }

            if !spel.rondes.isEmpty {
                Section("Rondes") {
                    ForEach(Array(spel.rondes.enumerated()).reversed(), id: \.offset) { paar in
                        HStack(alignment: .firstTextBaseline) {
                            Text("Ronde \(paar.offset + 1)").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text(verbatim: paar.element.map(String.init).joined(separator: "  ·  ")).monospacedDigit()
                        }
                    }
                    .onDelete { weg in
                        let n = spel.rondes.count
                        for i in weg.map({ n - 1 - $0 }).sorted(by: >) { spel.rondes.remove(at: i) }
                    }
                }
            }

            Section {
                Toggle("Laagste score wint", isOn: $spel.laagsteWint)
                HStack {
                    Text("Spelen tot")
                    Spacer()
                    TextField("geen doel", value: $spel.doel, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                }
                Button("Nieuw spel, zelfde spelers") { spel.rondes = []; invoer = [] }
                    .disabled(spel.rondes.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy, value: spel)
        .onAppear {
            if let data = opgeslagen.data(using: .utf8), let s = try? JSONDecoder().decode(Spel.self, from: data) { spel = s }
        }
        .onChange(of: spel) {
            if let data = try? JSONEncoder().encode(spel) { opgeslagen = String(decoding: data, as: UTF8.self) }
        }
    }

    private func voegToe() {
        let naam = nieuweSpeler.trimmingCharacters(in: .whitespaces)
        guard !naam.isEmpty else { return }
        spel.spelers.append(naam)
        for r in spel.rondes.indices { spel.rondes[r].append(0) }
        nieuweSpeler = ""
    }

    private func binding(_ i: Int) -> Binding<String> {
        Binding(get: { invoer[safe: i] ?? "" },
                set: { nieuw in
                    while invoer.count <= i { invoer.append("") }
                    invoer[i] = nieuw
                })
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
