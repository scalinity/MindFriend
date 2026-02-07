import SwiftUI
import PencilKit

struct DrawingCanvasView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @StateObject private var drawingState = DrawingState()
    @State private var showSaveSheet = false
    @State private var drawingTitle = ""
    @State private var moodScore: Int = 5
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // Canvas
                DrawingCanvas(drawingState: drawingState)
                    .ignoresSafeArea(edges: .bottom)

                // Toolbar overlay at bottom
                VStack {
                    Spacer()
                    drawingToolbar
                }
            }
            .navigationTitle("Draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            drawingState.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(!drawingState.canUndo)

                        Button {
                            drawingState.redo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                        }
                        .disabled(!drawingState.canRedo)

                        Button {
                            showSaveSheet = true
                        } label: {
                            Text("Save")
                                .bold()
                        }
                        .disabled(!drawingState.hasContent)
                    }
                }
            }
            .sheet(isPresented: $showSaveSheet) {
                saveDrawingSheet
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                if let error = error {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Drawing Toolbar

    private var drawingToolbar: some View {
        VStack(spacing: 12) {
            // Tool selection
            HStack(spacing: 16) {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    Button {
                        drawingState.selectedTool = tool
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.icon)
                                .font(.title3)
                            Text(tool.displayName)
                                .font(.caption2)
                        }
                        .frame(width: 50)
                        .padding(.vertical, 8)
                        .background(drawingState.selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(8)
                    }
                    .foregroundStyle(drawingState.selectedTool == tool ? .primary : .secondary)
                }
            }

            // Color picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(DrawingState.presetColors, id: \.self) { color in
                        Button {
                            drawingState.selectedColor = color
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Circle()
                                        .stroke(drawingState.selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                }
                        }
                    }

                    ColorPicker("", selection: $drawingState.selectedColor)
                        .labelsHidden()
                        .frame(width: 32, height: 32)
                }
                .padding(.horizontal)
            }

            // Brush size slider
            HStack {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Slider(value: $drawingState.lineWidth, in: 1...30)
                    .frame(maxWidth: 200)

                Image(systemName: "circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Save Sheet

    private var saveDrawingSheet: some View {
        NavigationStack {
            Form {
                Section("Title (optional)") {
                    TextField("My drawing", text: $drawingTitle)
                }

                Section("How do you feel?") {
                    HStack {
                        Text("Mood")
                        Spacer()
                        Text("\(moodScore)/10")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(moodScore) },
                            set: { moodScore = Int($0) }
                        ),
                        in: 1...10,
                        step: 1
                    )
                }
            }
            .navigationTitle("Save Drawing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showSaveSheet = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveDrawing() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .bold()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveDrawing() async {
        isSaving = true

        do {
            // Render drawing to image
            guard let imageData = drawingState.renderToImage() else {
                error = "Failed to render drawing"
                isSaving = false
                return
            }

            // Get canvas size
            let canvasSize = UIScreen.main.bounds.size

            // Save to service
            _ = try await container.creativeExpressionService.saveDrawing(
                strokes: drawingState.generateStrokes(),
                canvasSize: canvasSize,
                imageData: imageData,
                title: drawingTitle.isEmpty ? nil : drawingTitle,
                moodScore: moodScore
            )

            showSaveSheet = false
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Drawing State

@MainActor
class DrawingState: ObservableObject {
    @Published var selectedTool: DrawingTool = .pen
    @Published var selectedColor: Color = .black
    @Published var lineWidth: CGFloat = 5
    @Published var canvasView = PKCanvasView()

    // Undo/Redo/Save state
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    @Published var hasContent: Bool = false

    static let presetColors: [Color] = [
        .black, .gray, .red, .orange, .yellow, .green, .blue, .purple, .pink, .brown
    ]

    init() {
        setupCanvas()
    }

    private func setupCanvas() {
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvasView.backgroundColor = .white
        canvasView.becomeFirstResponder()
    }

    func undo() {
        canvasView.undoManager?.undo()
    }

    func redo() {
        canvasView.undoManager?.redo()
    }
    
    func clear() {
        canvasView.drawing = PKDrawing()
        updateState()
    }
    
    func updateState() {
        canUndo = canvasView.undoManager?.canUndo ?? false
        canRedo = canvasView.undoManager?.canRedo ?? false
        hasContent = !canvasView.drawing.strokes.isEmpty
    }

    func renderToImage() -> Data? {
        let renderer = UIGraphicsImageRenderer(bounds: canvasView.bounds)
        let image = renderer.image { context in
            // Fill background with white since PKCanvasView is transparent by default in some contexts
            UIColor.white.setFill()
            context.fill(canvasView.bounds)
            
            canvasView.drawHierarchy(in: canvasView.bounds, afterScreenUpdates: true)
        }
        return image.pngData()
    }
    
    /// Convert PKDrawing to simplified DrawingStroke model for storage/replay
    func generateStrokes() -> [DrawingStroke] {
        return canvasView.drawing.strokes.compactMap { pkStroke -> DrawingStroke? in
            // Map PKInkType to DrawingTool
            let tool: DrawingTool
            switch pkStroke.ink.inkType {
            case .pen: tool = .pen
            case .marker: tool = .marker
            case .watercolor: tool = .watercolor
            default: tool = .pen
            }
            
            // Extract points
            let points = pkStroke.path.compactMap { $0.location }
            guard !points.isEmpty else { return nil }
            
            // Approximate width from the first point of the path
            // PKStroke doesn't expose a global width, so we take a sample
            let approxWidth = pkStroke.path.first?.size.width ?? 5.0
            
            return DrawingStroke(
                id: UUID(),
                points: points,
                color: hexString(from: pkStroke.ink.color),
                lineWidth: approxWidth,
                tool: tool,
                opacity: 1.0 // Opacity is usually baked into the color in PK
            )
        }
    }

    private func hexString(from color: Color) -> String {
        return hexString(from: UIColor(color))
    }

    private func hexString(from uiColor: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        // Handle monochrome (black/white) explicitly if getRed fails or returns monochrome
        if !uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            // Try getWhite for monochrome colors
            var white: CGFloat = 0
            if uiColor.getWhite(&white, alpha: &alpha) {
                red = white
                green = white
                blue = white
            }
        }

        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    func updateTool() {
        let pkTool: PKTool
        let uiColor = UIColor(selectedColor)

        switch selectedTool {
        case .pen:
            pkTool = PKInkingTool(.pen, color: uiColor, width: lineWidth)
        case .marker:
            pkTool = PKInkingTool(.marker, color: uiColor, width: lineWidth)
        case .watercolor:
            pkTool = PKInkingTool(.watercolor, color: uiColor.withAlphaComponent(0.5), width: lineWidth)
        case .eraser:
            pkTool = PKEraserTool(.vector)
        }

        canvasView.tool = pkTool
    }
}

// MARK: - Drawing Canvas (PencilKit wrapper)

struct DrawingCanvas: UIViewRepresentable {
    @ObservedObject var drawingState: DrawingState

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = drawingState.canvasView
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        drawingState.updateTool()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingState: drawingState)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let drawingState: DrawingState

        init(drawingState: DrawingState) {
            self.drawingState = drawingState
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            DispatchQueue.main.async {
                self.drawingState.updateState()
            }
        }
    }
}

// MARK: - Creative Exercises List View

struct CreativeExercisesListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var exercises: [CreativeExercise] = []
    @State private var selectedCategory: CreativeExerciseCategory?
    @State private var isLoading = true

    var filteredExercises: [CreativeExercise] {
        guard let category = selectedCategory else { return exercises }
        return exercises.filter { $0.category == category }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            label: "All",
                            isSelected: selectedCategory == nil,
                            action: { selectedCategory = nil }
                        )

                        ForEach(CreativeExerciseCategory.allCases, id: \.self) { category in
                            FilterChip(
                                label: category.displayName,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                // Exercises list
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if filteredExercises.isEmpty {
                    ContentUnavailableView(
                        "No Exercises",
                        systemImage: "paintpalette",
                        description: Text("Check back soon for new creative exercises")
                    )
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredExercises) { exercise in
                            NavigationLink {
                                CreativeExerciseDetailView(exercise: exercise)
                            } label: {
                                CreativeExerciseCard(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Creative Exercises")
        .task {
            await loadExercises()
        }
    }

    private func loadExercises() async {
        isLoading = true
        defer { isLoading = false }

        do {
            exercises = try await container.creativeExpressionService.fetchExercises()
        } catch {
            Log.creative.error("Failed to load exercises", error: error)
        }
    }
}

struct CreativeExerciseCard: View {
    let exercise: CreativeExercise

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: exercise.exerciseType.icon)
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .frame(width: 60, height: 60)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(exercise.title)
                        .font(.headline)

                    if exercise.isPremium {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                Text(exercise.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label("\(exercise.estimatedMinutes) min", systemImage: "clock")
                    Label(exercise.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct CreativeExerciseDetailView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let exercise: CreativeExercise
    @State private var completionId: String?
    @State private var moodBefore: Int = 5
    @State private var moodAfter: Int = 5
    @State private var reflection = ""
    @State private var isStarted = false
    @State private var isComplete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: exercise.exerciseType.icon)
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 80, height: 80)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.title2.bold())

                        HStack(spacing: 12) {
                            Label("\(exercise.estimatedMinutes) min", systemImage: "clock")
                            Label(exercise.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                // Description
                Text(exercise.description)
                    .font(.body)

                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions")
                        .font(.headline)

                    Text(exercise.instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if isStarted && !isComplete {
                    // Mood before
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How do you feel before starting?")
                            .font(.headline)

                        HStack {
                            Text("Low")
                            Slider(
                                value: Binding(
                                    get: { Double(moodBefore) },
                                    set: { moodBefore = Int($0) }
                                ),
                                in: 1...10,
                                step: 1
                            )
                            Text("High")
                        }
                        .font(.caption)
                    }
                }

                if isComplete {
                    // Mood after
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How do you feel now?")
                            .font(.headline)

                        HStack {
                            Text("Low")
                            Slider(
                                value: Binding(
                                    get: { Double(moodAfter) },
                                    set: { moodAfter = Int($0) }
                                ),
                                in: 1...10,
                                step: 1
                            )
                            Text("High")
                        }
                        .font(.caption)
                    }

                    // Reflection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reflection (optional)")
                            .font(.headline)

                        TextField("What did you notice during this exercise?", text: $reflection, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }
                }

                Spacer(minLength: 20)

                // Action button
                if !isStarted {
                    Button {
                        Task { await startExercise() }
                    } label: {
                        Text("Start Exercise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                } else if !isComplete {
                    Button {
                        isComplete = true
                    } label: {
                        Text("I'm Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                } else {
                    Button {
                        Task { await completeExercise() }
                    } label: {
                        Text("Complete & Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startExercise() async {
        do {
            completionId = try await container.creativeExpressionService.startExercise(exerciseId: exercise.id)
            isStarted = true
        } catch {
            Log.creative.error("Failed to start exercise", error: error)
            isStarted = true // Allow to continue even if tracking fails
        }
    }

    private func completeExercise() async {
        guard let completionId = completionId else {
            dismiss()
            return
        }

        do {
            try await container.creativeExpressionService.completeExercise(
                completionId: completionId,
                creativeWorkId: nil,
                reflection: reflection.isEmpty ? nil : reflection,
                moodBefore: moodBefore,
                moodAfter: moodAfter
            )
        } catch {
            Log.creative.error("Failed to complete exercise", error: error)
        }

        dismiss()
    }
}

#Preview {
    DrawingCanvasView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
