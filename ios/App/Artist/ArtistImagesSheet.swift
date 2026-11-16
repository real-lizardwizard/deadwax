import DeadwaxCore
import SwiftUI

/// Artist images (Phase 8, slice 5 - phase8-managing.md 4; the web's ImagesBody): a sheet with its own stack, from the
/// artist page's •••. Who the pictures are of ("Showing Ye (rapper)", with Not them? and the search), the notes on the
/// sources it couldn't ask, then a section per slot (the preview's `kinds`, their labels): the picture chosen for it
/// large - or what is on disk, or that nothing was found - and Use another picture (N), N the pictures of every other
/// kind, as the web counts them (ArtistManage.anotherPicture), pushing every picture the slot can take as a grid, its own
/// kind's first; a tap chooses one and a second takes it back (toggleChoice). With no other kind's to offer, the slot's
/// own still need the grid on a phone (the slot draws only the one chosen): "Pictures for this slot (N)". Then Replace
/// pictures that are already there, what is in their folder now, and Save - on only as Core's ArtistImagesFlow.canSave
/// says - with what it wrote (savedLine) under it, and a choice a look no longer offers said (notOffered).
///
/// Every picture of a candidate comes through deadwax's relay (RelayedArtistPicture): the phone talks only to deadwax.
/// One the relay couldn't pass on is drawn as words, never a blank. Pictures load as they are drawn (the grid is lazy),
/// at most four at a time.
///
/// It needs deadwax (phase8-managing.md 2): opened out of reach, it says so and asks nothing, opening by itself once
/// deadwax is back; gone out of reach, what is drawn stays under the amber line, Save off - and back, the look is asked
/// again before Save comes back. With choices or Replace changed and not saved, a swipe doesn't close it and Close asks;
/// while Save runs, Close is off.
struct ArtistImagesSheet: View {
    let request: ArtistImagesRequest
    let onSaved: () -> Void

    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ArtistImagesModel?
    @State private var askingDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    ArtistImagesRoot(model: model)
                } else {
                    Color.clear
                }
            }
            .navigationTitle(ArtistManageWords.imagesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EditWords.close, action: close)
                        .disabled(model?.flow.saving == true)
                        .confirmationDialog(EditWords.discardTitle, isPresented: $askingDiscard, titleVisibility: .visible) {
                            Button(EditWords.discard, role: .destructive) { dismiss() }
                            Button(EditWords.keepEditing, role: .cancel) {}
                        }
                }
            }
            .navigationDestination(for: ArtistImageSlot.self) { (slot: ArtistImageSlot) in
                if let model {
                    ArtistPictureGrid(model: model, slot: slot)
                        .editOutOfReach(!model.flow.online)
                }
            }
        }
        .interactiveDismissDisabled(model?.flow.holdsWork == true || model?.flow.saving == true)
        .task {
            if model == nil {
                let made = ArtistImagesModel(request: request, client: server.client, admin: server.access.seesDetail,
                                             online: reachability.online)
                made.attach(navigation)
                made.onSaved = onSaved
                model = made
            }
            await model?.open()
        }
        .onChange(of: reachability.online) { _, now in
            Task { await model?.reach(now) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model?.becameActive() }
        }
    }

    private func close() {
        guard let model, !model.flow.saving else { return }
        if model.flow.holdsWork {
            askingDiscard = true
        } else {
            dismiss()
        }
    }
}

/// A slot of Artist images, pushed as its grid: its kind and its label.
struct ArtistImageSlot: Hashable {
    let kind: String
    let label: String
}

/// Artist images' page: everything ArtistImagesSheet says, as sections of one list.
private struct ArtistImagesRoot: View {
    let model: ArtistImagesModel

    @FocusState private var searchFocused: Bool

    var body: some View {
        let flow = model.flow
        Group {
            if let reason = model.reason {
                // no one folder takes their pictures: why, and nothing asked
                List {
                    Section {
                        Text(reason)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if !flow.online && flow.preview == nil && flow.loading == nil && flow.problem == nil {
                // opened out of reach: nothing asked, nothing drawn as if live
                ContentUnavailableView {
                    Label(ArtistManageWords.imagesTitle, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                List {
                    if flow.mayHaveFinished {
                        // kept whatever the look after it does - a look that fails leaves it said
                        Section {
                            MayHaveFinished(reading: flow.loading != nil)
                        }
                    }
                    who(flow)
                    if flow.searchOpen { searchSections(flow) }
                    if let name = flow.loading {
                        Section {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(ArtistManageWords.looking(name))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } else if let problem = flow.problem {
                        Section {
                            ReadAgainFailed(failure: problem, disabled: !flow.online) {
                                Task { await model.lookAgain() }
                            }
                        }
                    } else if let preview = flow.preview {
                        found(preview, flow: flow)
                    }
                }
            }
        }
        .editOutOfReach(!flow.online && model.reason == nil && (flow.preview != nil || flow.problem != nil))
    }

    /// "Showing Ye (rapper)", with Not them? while the search is closed - once the pictures of someone are drawn.
    @ViewBuilder private func who(_ flow: ArtistImagesFlow) -> some View {
        if let preview = flow.preview, preview.mbid != nil, flow.loading == nil {
            Section {
                let name = ArtistManage.showingWho(factsName: preview.facts?.name, pageName: model.pageName)
                Text(ArtistManage.showing(name, disambiguation: preview.facts?.disambiguation ?? ""))
                    .font(Typeface.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if !flow.searchOpen {
                    Button(ArtistManageWords.notThem) {
                        model.openSearch()
                        searchFocused = true
                    }
                    .disabled(flow.saving)
                }
            }
        }
    }

    /// The search: its field and Search, what it found (a pick looks for that artist's pictures), and its note.
    @ViewBuilder private func searchSections(_ flow: ArtistImagesFlow) -> some View {
        @Bindable var model = model
        Section {
            HStack(spacing: 10) {
                TextField(ArtistManageWords.searchLabel, text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { Task { await model.search() } }
                if flow.searching { ProgressView() }
                Button(ArtistManageWords.search) {
                    Task { await model.search() }
                }
                .disabled(ArtistManage.searchWords(model.query).isEmpty || !flow.online || flow.saving)
            }
            if let note = flow.searchNote {
                Text(note)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(ArtistManageWords.searchLabel)
                .font(Typeface.footnote)
        }
        if !flow.matches.isEmpty {
            Section {
                ForEach(flow.matches, id: \.mbid) { (match: MBArtistMatch) in
                    ArtistMatchRow(match: match) {
                        Task { await model.look(mbid: match.mbid, name: match.name) }
                    }
                    .disabled(!flow.online || flow.saving)
                }
            } header: {
                Text(ArtistManageWords.whichArtist)
                    .font(Typeface.footnote)
            }
        }
    }

    /// What the look found: the notes, each slot, Replace, the folder now and Save.
    @ViewBuilder private func found(_ preview: ArtistImagesPreview, flow: ArtistImagesFlow) -> some View {
        let notes = preview.notes
        if preview.mbid == nil || !notes.isEmpty || !preview.problems.isEmpty {
            Section {
                // with no one settled, the problems first, as warnings; settled, after the notes, as notes
                if preview.mbid == nil {
                    ForEach(Array(preview.problems.enumerated()), id: \.offset) { (_: Int, said: String) in
                        Text(said)
                            .foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(Array(notes.enumerated()), id: \.offset) { (_: Int, note: String) in
                    Text(note)
                        .font(Typeface.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if preview.mbid != nil {
                    ForEach(Array(preview.problems.enumerated()), id: \.offset) { (_: Int, said: String) in
                        Text(said)
                            .font(Typeface.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if preview.mbid != nil, let dropped = flow.notOffered {
            Section {
                Text(dropped)
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if preview.mbid != nil {
            let grouped = ArtistManage.byKind(preview.candidates)
            ForEach(preview.kinds, id: \.kind) { (slot: ArtistImageKind) in
                slotSection(slot, options: grouped[slot.kind] ?? [], preview: preview, flow: flow)
            }
            saving(preview, flow: flow)
        }
    }

    @ViewBuilder private func slotSection(_ slot: ArtistImageKind, options: [ArtistImageCandidate],
                                          preview: ArtistImagesPreview, flow: ArtistImagesFlow) -> some View {
        let existing = preview.art[slot.kind]
        let line = ArtistManage.slotLine(existing: existing, found: options.count)
        let every = options + ArtistManage.others(preview.candidates, kind: slot.kind)
        // the web's button, counted as it counts it; the slot's own pictures alone still need the grid here
        let another = ArtistManage.anotherPicture(preview.candidates, kind: slot.kind)
            ?? (options.isEmpty ? nil : ArtistManageWords.slotPictures(options.count))
        let chosen = flow.chosen[slot.kind].flatMap { (url: String) -> ArtistImageCandidate? in
            every.first { ArtistManage.sameAddress($0.url, url) }
        }
        Section {
            if let chosen {
                VStack(alignment: .leading, spacing: 6) {
                    RelayedArtistPicture(candidate: chosen, square: slot.kind == "thumb")
                        .frame(maxWidth: slot.kind == "thumb" ? 240 : .infinity)
                    Label(ArtistManageWords.asWords(chosen), systemImage: "checkmark")
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ArtistManageWords.option(chosen))
                .accessibilityValue(ArtistManageWords.chosenMark)
            } else if let existing, !existing.isEmpty, let path = preview.path, !path.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ArtistFolderPicture(path: path, kind: slot.kind, square: slot.kind == "thumb")
                        .frame(maxWidth: slot.kind == "thumb" ? 240 : .infinity)
                    Text(ArtistManageWords.onDisk(slot.label))
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .combine)
            }
            if let another {
                NavigationLink(value: ArtistImageSlot(kind: slot.kind, label: slot.label)) {
                    Text(another)
                }
                .disabled(flow.saving)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(slot.label)
                if !line.isEmpty {
                    Spacer(minLength: 8)
                    Text(line)
                }
            }
            .font(Typeface.footnote)
        }
    }

    /// Replace, what is in their folder now, Save and what it said.
    @ViewBuilder private func saving(_ preview: ArtistImagesPreview, flow: ArtistImagesFlow) -> some View {
        @Bindable var model = model
        Section {
            Toggle(ArtistManageWords.replace, isOn: $model.replace)
                .disabled(flow.saving)
        }
        let kept = preview.kinds.filter { (slot: ArtistImageKind) -> Bool in
            !(preview.art[slot.kind] ?? "").isEmpty
        }
        if !kept.isEmpty, let path = preview.path, !path.isEmpty {
            Section {
                ForEach(kept, id: \.kind) { (slot: ArtistImageKind) in
                    HStack(spacing: 12) {
                        ArtistFolderPicture(path: path, kind: slot.kind, square: slot.kind == "thumb")
                            .frame(width: slot.kind == "thumb" ? 48 : 86)
                            .clipShape(Corners.artShape)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.label)
                            Text(preview.art[slot.kind] ?? "")
                                .font(Typeface.mono(.caption))
                                .foregroundStyle(Palette.quiet)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(ArtistManageWords.inFolder)
                    .font(Typeface.footnote)
            }
        }
        Section {
            Button {
                Task { await model.save() }
            } label: {
                HStack(spacing: 10) {
                    if flow.saving { ProgressView() }
                    Text(flow.saving ? ArtistManageWords.saving : ArtistManageWords.save)
                }
            }
            .disabled(!flow.canSave)
            if let saved = flow.saved, !saved.isEmpty {
                Text(saved)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Use another picture: every picture a slot can take - its own kind's first, then the rest found - as a grid, each
/// with where it is from; a tap chooses it for the slot, a tap on the one chosen takes it back (that slot isn't
/// written). Lazy: a picture is asked only once it is near the screen.
private struct ArtistPictureGrid: View {
    let model: ArtistImagesModel
    let slot: ArtistImageSlot

    var body: some View {
        let flow = model.flow
        let candidates = flow.preview?.candidates ?? []
        let every = candidates.filter { $0.kind == slot.kind } + ArtistManage.others(candidates, kind: slot.kind)
        let square = slot.kind == "thumb"
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: square ? 130 : 160), spacing: 12)], spacing: 16) {
                ForEach(Array(every.enumerated()), id: \.offset) { (_: Int, candidate: ArtistImageCandidate) in
                    let on = flow.isChosen(kind: slot.kind, url: candidate.url)
                    Button {
                        model.toggle(kind: slot.kind, url: candidate.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            RelayedArtistPicture(candidate: candidate, square: square)
                                .overlay {
                                    if on {
                                        Corners.artShape
                                            .strokeBorder(Palette.accent, lineWidth: 3)
                                    }
                                }
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                if on {
                                    Image(systemName: "checkmark")
                                        .font(Typeface.symbol(.caption2).weight(.bold))
                                        .foregroundStyle(Palette.accent)
                                }
                                Text(ArtistManageWords.asWords(candidate))
                                    .font(Typeface.caption)
                                    .foregroundStyle(Palette.quiet)
                                    .lineLimit(2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(flow.saving)
                    .accessibilityLabel(ArtistManageWords.option(candidate))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(16)
        }
        .navigationTitle(slot.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One of MusicBrainz's artists for a name (the web's MatchList row): their name, and what tells them apart
/// (matchLine) - a tap takes them.
struct ArtistMatchRow: View {
    let match: MBArtistMatch
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.name)
                    .foregroundStyle(.primary)
                let line = ArtistManage.matchLine(match)
                if !line.isEmpty {
                    Text(line)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }
}
