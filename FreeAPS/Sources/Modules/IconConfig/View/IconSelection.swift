import SwiftUI

struct IconSelection: View {
    @EnvironmentObject var model: Icons

    var body: some View {
        let columns = Array(repeating: GridItem(.adaptive(minimum: 114, maximum: 1024), spacing: 0), count: 3)

        VStack {
            HStack {
                Text("iAPS Icon")
                    .font(.title)
                Image(model.appIcon.preview)
                    .resizable()
                    .frame(maxWidth: 60, maxHeight: 60)
            }

            Divider()

            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEach(Icon_.allCases) { icon in
                        Button { model.setAlternateAppIcon(icon: icon) }
                        label: { Image(icon.preview)
                            .resizable()
                            .frame(maxWidth: 80, maxHeight: 80)
                        }.padding(.vertical, 15)
                    }
                }
            }
        }
    }
}

struct IconSelectionRootView_Previews: PreviewProvider {
    static var previews: some View {
        IconSelection()
            .environmentObject(Icons())
    }
}
