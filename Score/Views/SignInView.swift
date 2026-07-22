import SwiftUI
import LocalAuthentication

struct SignInView: View {
    @Environment(ScoreStore.self) private var store
    @State private var name = ""
    @State private var email = ""
    @State private var role = AccountRole.student
    @State private var biometricsAvailable = false
    @State private var showManualFallback = false
    @State private var isAuthenticating = false
    
    var body: some View {
        ZStack {
            // Dynamic background gradient
            LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // App Branding
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .cyan.opacity(0.5), radius: 10)
                    
                    Text("SCORE")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .tracking(8)
                        .foregroundStyle(.white)
                    
                    Text("A live teaching instrument for Crafting AI")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Onboarding Options Selection
                if !showManualFallback {
                    VStack(spacing: 20) {
                        Text("Choose your role to begin")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 24) {
                            // Student Card
                            RoleCardView(
                                title: "Student",
                                subtitle: "Access presentations, track weeks & log pulses",
                                icon: "laptopcomputer",
                                color: .cyan,
                                action: { selectRoleAndAuthenticate(.student) }
                            )
                            
                            // Instructor Card
                            RoleCardView(
                                title: "Instructor",
                                subtitle: "Control live slides, manage weeks & constitution",
                                icon: "crown.fill",
                                color: .purple,
                                action: { selectRoleAndAuthenticate(.instructor) }
                            )
                        }
                        .frame(maxWidth: 620)
                        
                        // Quick fallback link
                        Button("Manual Login Profile") {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                showManualFallback = true
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                        .padding(.top, 10)
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
                } else {
                    // Manual Fallback Form View
                    VStack(spacing: 16) {
                        HStack {
                            Text("Manual Profile Entry")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    showManualFallback = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                        TextField("Email", text: $email).textFieldStyle(.roundedBorder)
                        Picker("Enter as", selection: $role) {
                            ForEach(AccountRole.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                        
                        Button {
                            Task {
                                await store.signIn(name: name, email: email, role: role)
                            }
                        } label: {
                            HStack {
                                if store.isWorking { ProgressView() }
                                Text("Enter the studio")
                              }
                              .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(name.isEmpty || email.isEmpty || store.isWorking)
                        
                        if biometricsAvailable {
                            Button(action: { selectRoleAndAuthenticate(role) }) {
                                Label("Sign in with Touch ID", systemImage: "touchid")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(.cyan)
                        }
                    }
                    .padding(26)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .frame(maxWidth: 420)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
                
                if isAuthenticating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Touch ID credentials...").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                Text("Connects to the Score server when available; otherwise opens in local demo mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        }
        .onAppear {
            let context = LAContext()
            biometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        }
    }
    
    private func selectRoleAndAuthenticate(_ selectedRole: AccountRole) {
        self.role = selectedRole
        if biometricsAvailable {
            authenticateWithBiometrics()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showManualFallback = true
            }
        }
    }
    
    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            isAuthenticating = true
            let reason = "Unlock Score with your secure biometric credentials."
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
                DispatchQueue.main.async {
                    isAuthenticating = false
                    if success {
                        Task {
                            #if os(macOS)
                            let localName = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
                            let emailUsername = NSUserName()
                            #else
                            let localName = role == .student ? "Student" : "Instructor"
                            let emailUsername = role == .student ? "student" : "instructor"
                            #endif
                            await store.signIn(
                                name: localName,
                                email: "\(emailUsername)@local.craftingai.uwm.edu",
                                role: role
                            )
                        }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            showManualFallback = true
                        }
                    }
                }
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showManualFallback = true
            }
        }
    }
}

struct RoleCardView: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(isHovering ? 0.8 : 0.4), radius: 6)
                
                VStack(spacing: 4) {
                    Text(title.uppercased())
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        isHovering ? color.opacity(0.8) : Color.white.opacity(0.1),
                        lineWidth: isHovering ? 2.5 : 1
                    )
            )
            .shadow(color: isHovering ? color.opacity(0.3) : Color.black.opacity(0.2), radius: isHovering ? 15 : 6)
            .scaleEffect(isHovering ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
}
