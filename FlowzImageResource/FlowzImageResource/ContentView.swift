//
//  ContentView.swift
//  FlowzImageResource
//
//  Created by 千千 on 4/8/24.
//

import SwiftUI
import AppKit

struct ContentView: View {

    @ObservedObject var viewModel = ViewModel()
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    if let folder = viewModel.selectedFolder {
                        Text("\(folder)")
                    } else {
                        Text("请选择项目路径")
                    }
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                        .onTapGesture {
                            viewModel.selectFolder()
                        }
                    Button("扫描仓库，生成初始Plist") {
                        viewModel.scanPathImage()
                    }
//                    Button("更新UI") {
//                        viewModel.refreshNewImageList()
//                    }
                    Button("扫描代码，更新Plist-inUse属性") {
                        viewModel.scanCodeUpdatePlist()
                    }
                    Button("扫描仓库，更新Plist") {
                        viewModel.renewPlist()
                    }
                }
                List {
                    NavigationLink("全部图片") {
                        ScrollView {
                            VStack {
                                ForEach(viewModel.allImageList) { item in
                                    HStack {
                                        imageFromPath(item.path)
                                            .resizable()
                                            .frame(width: 50, height: 50)
                                        VStack(alignment: .leading) {
                                            Text("是否压缩: \(item.compressed ? "是" : "否")")
                                            Text("是否在使用: \(item.inUse ? "是" : "否")")
                                            Text("是否允许存在: \(item.isAllowUnused ? "是" : "否")")
                                        }
                                        Spacer()
                                    }
                                    .padding()
                                }
                            }
                        }
                    }
                    NavigationLink("未使用图片") {
                        ScrollView {
                            VStack {
                                Button("全部删除") {
                                    viewModel.deleteAllNoUseImage()
                                }
                                ForEach(viewModel.noUseList) { item in
                                    HStack {
                                        imageFromPath(item.path)
                                            .resizable()
                                            .frame(width: 50, height: 50)
                                        VStack(alignment: .leading) {
                                            Text("名称: \(item.path)")
                                            Text("是否压缩: \(item.compressed ? "是" : "否")")
                                            Text("是否在使用: \(item.inUse ? "是" : "否")")
                                            Text("是否允许存在: \(item.isAllowUnused ? "是" : "否")")
                                        //提供一个标记按钮
                                            Toggle(isOn: Binding<Bool>(
                                                get: { item.isAllowUnused },
                                                set: { newValue in
                                                    viewModel.updateIsAllowUnused(for: item.id, to: newValue)
                                                }
                                            )) {
                                                Text("是否允许存在")
                                            }
                                        //提供一个删除
                                        
                                        }
                                        Spacer()
                                    }
                                    .padding()
                                }
                            }
                        }
                    }
                    NavigationLink("未压缩图片") {
                        ScrollView {
                            VStack {
                                Button("全部压缩") {
                                    viewModel.compressAll()
                                }
                                ForEach(viewModel.noCompressList) { item in
                                    HStack {
                                        imageFromPath(item.path)
                                            .resizable()
                                            .frame(width: 50, height: 50)
                                        VStack(alignment: .leading) {
                                            Text("名称: \(item.path)")
                                            Text("是否压缩: \(item.compressed ? "是" : "否")")
                                            Text("是否在使用: \(item.inUse ? "是" : "否")")
                                        }
                                        Spacer()
                                    }
                                    .padding()
                                }
                            }
                        }
                    }
                    
                }
                
            }
        }
        

        .padding()
    }
    // 辅助函数：从给定路径加载UIImage，如果失败返回一个占位符UIImage
    private func imageFromPath(_ path: String) -> Image {
        if let uiImage = NSImage(contentsOfFile: path) {
            return Image(nsImage: uiImage)
        } else {
            // 如果图片加载失败，返回一个系统占位符图像
            return Image(systemName: "photo")
        }
    }
}

#Preview {
    ContentView()
}
