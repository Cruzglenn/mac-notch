import SwiftUI
import UniformTypeIdentifiers
import Defaults

struct NotchIntelligenceDropView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = IntelligenceDropManager.shared
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @State private var readingProgress: CGFloat = 0.0
    @State private var promptText: String = ""
    @State private var showModelPicker: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            switch manager.currentState {
            case .dropped:
                droppedStateView
            case .reading:
                readingStateView
            case .summary:
                summaryStateView
            }
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            vm.dropEvent = true
            Task {
                await manager.handleDrop(providers: providers)
            }
            return true
        }
        .popover(isPresented: $showModelPicker) {
            modelPickerView
        }
    }
    
    // MARK: - State 1: Dropped Files
    private var droppedStateView: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: manager.droppedFileType == "PDF" ? "doc.text.fill" : "photo.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.droppedFileName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(manager.droppedFileType)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                Button(action: { showModelPicker.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: Defaults[.selectedAIProvider].iconName)
                        Text(Defaults[.selectedAIProvider].displayName)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { manager.startReading() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 12, weight: .bold))
                        Text("Summarize")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { manager.reset() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
        .background(Color.black)
    }
    
    // MARK: - State 2: Reading
    private var readingStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.blue, .purple, .pink, .orange, .blue], center: .center))
                    .frame(width: 50, height: 50)
                    .blur(radius: 10)
                    .opacity(0.5)
                
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse)
            }
            
            VStack(spacing: 8) {
                Text("Analyzing Document...")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                ProgressView(value: readingProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(.orange)
                    .frame(width: 240, height: 4)
                    .clipShape(Capsule())
            }
        }
        .padding(30)
        .background(Color.black)
        .onAppear { 
            readingProgress = 0
            withAnimation(.linear(duration: 2.0)) { readingProgress = 1.0 } 
        }
    }
    
    // MARK: - State 3: Summary Output
    private var summaryStateView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Button(action: { manager.hasActiveDrop = false }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Image(systemName: "apple.intelligence")
                        .foregroundColor(.orange)
                        .font(.system(size: 16, weight: .bold))
                    Text("AI Summary")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                
                if screenAssistantManager.isLoading {
                    ProgressView().controlSize(.mini).padding(.leading, 4)
                }
                
                Spacer()
                
                Button(action: { showModelPicker.toggle() }) {
                    Text(Defaults[.selectedAIProvider].displayName)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }.buttonStyle(PlainButtonStyle())
                
                Button(action: { vm.close(); manager.reset() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray.opacity(0.6))
                }.buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 10)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if manager.summaryText.isEmpty {
                        HStack {
                            Spacer()
                            Text("Preparing analysis...")
                                .foregroundColor(.gray)
                                .italic()
                                .padding(.top, 40)
                            Spacer()
                        }
                    } else {
                        TypewriterText(manager.summaryText)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.95))
                            .lineSpacing(8)
                            .padding(.bottom, 40)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear { updateHeight(contentHeight: geo.size.height) }
                                        .onChange(of: geo.size.height) { _, newHeight in
                                            updateHeight(contentHeight: newHeight)
                                        }
                                }
                            )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            
            // Footer / Input
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 8)
                
                HStack(spacing: 12) {
                    TextField("Ask about this document...", text: $promptText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13))
                        .onSubmit { sendCustomPrompt() }
                    
                    Button(action: sendCustomPrompt) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.orange.gradient)
                    }.buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            if manager.contentHeight < 500 {
                manager.contentHeight = 520
            }
        }
        .background(Color.black)
    }
    
    private func sendCustomPrompt() {
        guard !promptText.isEmpty else { return }
        manager.startReading(customPrompt: promptText)
        promptText = ""
    }
    
    private func updateHeight(contentHeight: CGFloat) {
        // Base height for header and footer chrome
        let chromeHeight: CGFloat = 180
        let totalHeight = contentHeight + chromeHeight
        
        // Native feel: give it room. Min 520, Max capped in ContentView
        let targetHeight = max(totalHeight, 520)
        
        // Limit updates to prevent excessive re-renders during typewriter effect
        if abs(manager.contentHeight - targetHeight) > 10 {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                    manager.contentHeight = targetHeight
                }
            }
        }
    }
    
    private var modelPickerView: some View {
        VStack(spacing: 0) {
            Text("AI PROVIDER").font(.system(size: 10, weight: .black)).foregroundColor(.gray).padding(.top, 10)
            Divider().padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(AIModelProvider.allCases, id: \.self) { provider in
                        Button(action: { Defaults[.selectedAIProvider] = provider; showModelPicker = false }) {
                            HStack {
                                Image(systemName: provider.iconName).frame(width: 20)
                                Text(provider.displayName).font(.system(size: 12, weight: .medium))
                                Spacer()
                                if Defaults[.selectedAIProvider] == provider { Image(systemName: "checkmark.circle.fill").foregroundColor(.orange) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
            }.frame(height: 180)
        }.frame(width: 180).background(Color(nsColor: .windowBackgroundColor))
    }
}
