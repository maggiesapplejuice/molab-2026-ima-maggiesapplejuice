//
//  ContentView.swift
//  week3
//
//  Created by Maggie Lu on 9/18/26.
//

import SwiftUI

struct ContentView2: View {
    @state var count = 0
    var body: some View {
        VStack {
            Text("count \(count)"
                .font(.system(size: 60)),
                  Spacer()
                 switch count {
            case 0 :
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode:.fit)
                break
            case 1:
                Image(systemName: "apple.logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                break
            case 2:
                Image(systemName:dog
                
            } count == 0 ? "globe" : "apple.logo")
                 resizable()
                .aspectRatio(contentMode: .fit)
                 Spacer()
                 HStack{
                Button("Up") {
                    count += 1
                    print("Up count \(count)")
                }
                .buttonStyle(.bordered)
                .font(.system)(size:60))
                Button("Down"){
                    count -=1
                    print("Down count \(count)")
                }
                .buttonStyle(.bordered)
                .font(.system(size:60))
            }
        }
    }
}

