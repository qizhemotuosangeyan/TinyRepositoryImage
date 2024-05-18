//
//  ViewModel.swift
//  FlowzImageResource
//
//  Created by 千千 on 4/8/24.
//

import SwiftUI
import AppKit



class ViewModel: ObservableObject {
    @Published var selectedFolder: String?
    @Published var allImageList: [ImageItem]
    
    var noUseList: [ImageItem] {
            allImageList.filter { !$0.inUse }
        }
    var noCompressList: [ImageItem] {
        allImageList.filter { !$0.compressed }
    }
    
    let plistPath = "/Users/qianqian/Documents/flowz-ios/TestPropertyList.plist"
//    let plistPath = "/Users/qianqian/Desktop/ImageTestProject/TestPropertyList.plist"
    init(selectedFolder: String? = "/Users/qianqian/Documents/flowz-ios", allImageList: [ImageItem] = [ImageItem]()) {
        self.selectedFolder = selectedFolder
        self.allImageList = allImageList
        
        // 尝试修改文件权限为所有人可读可写 (666)
       let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o666]
        do {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: plistPath)
        } catch {
                print("——————修改文件权限失败")
        }
        //读取
        if let imageList = readImageList(from: plistPath) {
            self.allImageList = imageList
        }
    }
    func selectFolder() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.begin { result in
            if result == .OK, let selectedURL = openPanel.url {
                DispatchQueue.main.async {
                    self.selectedFolder = selectedURL.path
                }
            }
        }
    }
    //更新授权
    func updateIsAllowUnused(for itemID: UUID, to value: Bool) {
        if let index = allImageList.firstIndex(where: { $0.id == itemID }) {
            objectWillChange.send()
            allImageList[index].isAllowUnused = value
            // 更新 plist 文件
            updatePlistWithCurrentImageList()
        }
    }

    func compressAll() {
        noCompressList.forEach { compressImage(item: $0) }
    }
    // 调用这个方法来压缩图片
    func compressImage(item: ImageItem) {
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: item.path)) else {
            print("Unable to load image data.")
            return
        }

        print(item.path)
        // 准备 URL 和 URLRequest
        let url = URL(string: "https://api.tinify.com/shrink")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // 设置请求头
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        // 准备 API 密钥的 Base64 编码认证头
        let apiKey = "s8pqvhFDrKxRSpLWn8tjRQWpQryJQW30"
        let credentials = "api:\(apiKey)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            print("Error encoding credentials.")
            return
        }
        let base64Credentials = credentialsData.base64EncodedString(options: [])
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData
        print("请求头信息：\(request.allHTTPHeaderFields ?? [:])")
        // 检查 imageData 的内容，确认数据正确性
        print("将要发送的图像数据大小：\(imageData.count) 字节")

        // 发起网络请求
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("未收到 HTTP 响应。")
                    return
                }
                // 检查状态码并解析响应数据
                if httpResponse.statusCode == 201 {
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let output = json["output"] as? [String: Any],
                          let url = output["url"] as? String else {
                        print("无法解析响应数据。")
                        return
                    }
                    
                    print("压缩图片的 URL 是: \(url)")
                    //下载压缩后的图片
                    self.downloadCompressedImage(from: URL(string: url)!, for: item)
                } else {
                    // 服务器返回了错误状态码，尝试打印出响应体以获取错误详情
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("服务器响应状态码为：\(httpResponse.statusCode)")
                        print("响应正文：\(responseString)")
                    }
                }
            }
        task.resume()
    }
    
    private func downloadCompressedImage(from url: URL, for item: ImageItem) {
        let downloadTask = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Download failed: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            //下载成功后将下载到的图片
            self.updateImageItemWithData(data, for: item)
        }
        downloadTask.resume()
    }
       
    private func updateImageItemWithData(_ data: Data, for item: ImageItem) {
        // 写入数据到原路径
        do {
            try data.write(to: URL(fileURLWithPath: item.path))
            // 更新plist中的isCompressed属性
            if let index = self.allImageList.firstIndex(where: { $0.id == item.id }) {
                DispatchQueue.main.async {
                    self.allImageList[index].compressed = true
                }
                self.updatePlistWithCurrentImageList()
            }
        } catch {
            print("Failed to write image data: \(error)")
        }
    }
       
       // Helper function to load image data from a given path
    private func dataFromPath(_ path: String) -> Data? {
        return NSImage(contentsOfFile: path)?.tiffRepresentation
    }
    
    func scanPathImage() {
        guard let folderPath = selectedFolder else { return }
        //扫描拿到所有以WebP,JPEG和PNG为后缀文件
        let pathList = scanAllImages(in: folderPath)
        //写入
        for imagePath in pathList {
            if writeImageItem(to: plistPath, with: ImageItem(path: imagePath, inUse: false, compressed: false, isAllowUnused: false)) {
                print("\(folderPath)写入成功")
            }else {
                print("——————\(folderPath)写入失败")
            }
        }
        //读取
        if let imageList = readImageList(from: plistPath) {
            allImageList = imageList
        }
    }
    // 扫描代码比对plist文件，更新plist的未使用属性
    func scanCodeUpdatePlist() {
        guard let codeRepository = selectedFolder else { return }
        //Plist中的图片有两种使用方法：
        //1. 对于存放在Assets中的图片，做字符串切割，拿到图片的名称
        //TODO: 对于未存放在Assets中的图片，未处理
        //从Plist中读取最新Plist
        let imageNameList = getImageNameListFromAllImageList()

        searchForStrings(imageNameList, in: codeRepository) { matchedStr, matchedStrFilePath in
            // 此处已经匹配到了，将对应的Plist中的图片的inUse属性设置为true
            // 先去除可能的引号和点号
            var imageName = matchedStr.replacingOccurrences(of: "\"", with: "")
            imageName = imageName.replacingOccurrences(of: ".", with: "")
            // 再构造回原始的imageset路径格式
            let imageSetPath = "/\(imageName).imageset"
            print(imageSetPath) //打印结果："/imageIntroWorkingSchedule.imageset"
            //索引imageSetPath更新Plist的inUse属性
            let _ = self.updatePlistItem(forImageSetPath: imageSetPath, in: self.plistPath)
            self.refreshNewImageList()
        }

    }
    func renewPlist() {
        // 步骤1：扫描文件夹中的所有图片
        guard let folderPath = selectedFolder else { return }
        let scannedImagePaths = Set(scanAllImages(in: folderPath))

        // 步骤2：读取现有的plist中的图片
        guard var existingImages = readImageList(from: plistPath) else { return }

        // 步骤3：添加新的图片
        scannedImagePaths.forEach { path in
            if !existingImages.contains(where: { $0.path == path }) {
                // 如果这个路径的图片在现有的图片列表中不存在，则添加新的图片项
                let newItem = ImageItem(path: path, inUse: false, compressed: false, isAllowUnused: false)
                existingImages.append(newItem)
            }
        }
        
        // 步骤4：移除已删除的图片
        existingImages = existingImages.filter { item in
            scannedImagePaths.contains(item.path)
        }

        // 步骤5：更新plist文件
        updatePlist(with: existingImages)
        refreshNewImageList()
    }

    private func updatePlist(with imageList: [ImageItem]) {
        let fileURL = URL(fileURLWithPath: plistPath)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(imageList)
            try data.write(to: fileURL)
            print("plist successfully updated.")
        } catch {
            print("Failed to update plist: \(error)")
        }
    }

    func deleteAllNoUseImage() {
        
        // 准备 FileManager 实例用于删除文件
        let fileManager = FileManager.default
        
        // 通过过滤 noUseList 来获取所有未使用且不允许存在的图片项
        let toBeDeletedItems = noUseList.filter { !$0.isAllowUnused }
        
        // 准备一个数组来收集删除失败的项目，以便后续处理（如果需要）
        var deletionFailedItems: [ImageItem] = []
        
        for item in toBeDeletedItems {
            let imageURL = URL(fileURLWithPath: item.path)
            let imagesetFolderURL = imageURL.deletingLastPathComponent()
            
            do {
                if imagesetFolderURL.pathExtension == "imageset" {
                    // 尝试删除整个 .imageset 文件夹及其内容
                    try fileManager.removeItem(at: imagesetFolderURL)
                    print("Deleted .imageset folder: \(imagesetFolderURL.path)")
                } else {
                    // 如果不在 .imageset 文件夹中，仅删除图片文件
                    try fileManager.removeItem(atPath: item.path)
                    print("Deleted: \(item.path)")
                }
            } catch {
                print("Failed to delete: \(item.path) or its .imageset folder, error: \(error)")
                deletionFailedItems.append(item)
            }
        }
        
        // 更新 allImageList，移除已被成功删除且不允许存在的项
        allImageList.removeAll { item in
            toBeDeletedItems.contains(where: { $0.id == item.id }) && !deletionFailedItems.contains(where: { $0.id == item.id })
        }
        
        // 更新 plist 文件以反映当前的 allImageList 状态
        updatePlistWithCurrentImageList()
    }


    // 这个函数用于将更新后的 allImageList 写回 plist 文件
    private func updatePlistWithCurrentImageList() {
        let fileURL = URL(fileURLWithPath: plistPath)
        
        do {
            // 将更新后的图片列表编码为 plist 数据
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(allImageList)
            
            // 将编码后的数据写回 plist 文件
            try data.write(to: fileURL)
            print("plist updated successfully.")
        } catch {
            print("Failed to update plist: \(error)")
        }
    }

    private func updatePlistItem(forImageSetPath imageSetPath: String, in plistPath: String) -> Bool {
        let fileURL = URL(fileURLWithPath: plistPath)
        
        do {
            // 从plist读取图片列表
            let data = try Data(contentsOf: fileURL)
            var imageList = try PropertyListDecoder().decode([ImageItem].self, from: data)
            
            // 查找并更新匹配的ImageItem
            var isUpdated = false //加锁
            print(imageList[0].path)
            print(imageList[1].path)
            print(imageList[2].path)
            for index in 0..<imageList.count where imageList[index].path.contains(imageSetPath) {
                print(imageList[index])
                imageList[index].inUse = true
                isUpdated = true
            }
            
            guard isUpdated else { return false }
            // 将更新后的图片列表写回plist
            let updatedData = try PropertyListEncoder().encode(imageList)
            try updatedData.write(to: fileURL)
            return true
        } catch {
            print("更新失败: \(error)")
            return false
        }
    }
    
    private func getImageNameListFromAllImageList() -> Set<String> {
        let pattern = "\\/([^\\/]+)\\.imageset"
        var resultSet = Set<String>() // 使用集合来自动去重
        for image in allImageList {
            let imagePath = image.path
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let nsRange = NSRange(imagePath.startIndex..<imagePath.endIndex, in: imagePath)
                regex.enumerateMatches(in: imagePath, options: [], range: nsRange) { match, _, _ in
                    if let matchRange = match?.range(at: 1) {
                        let imageName = (imagePath as NSString).substring(with: matchRange)
                        resultSet.insert(imageName) // 插入到集合中
                    }
                }
            } catch {
                print("Regex error: \(error)")
            }
        }
        return resultSet
    }

    private func scanAllImages(in folderPath: String) -> [String] {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: folderPath)
        var imagePaths: [String] = []
        
        // 使用enumerator来递归遍历文件夹及其所有子文件夹
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: nil) {
            for case let fileURL as URL in enumerator {
                let fileExtension = fileURL.pathExtension.lowercased()
                if fileExtension == "webp" || fileExtension == "jpeg" || fileExtension == "png" {
                    imagePaths.append(fileURL.path)
                }
            }
        }
        
        return imagePaths
    }
    func refreshNewImageList() {
        if let imageList = readImageList(from: plistPath) {
            allImageList = imageList
        }
    }
    
    func readImageList(from plistPath: String) -> [ImageItem]? {
        let fileURL = URL(fileURLWithPath: plistPath)
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = PropertyListDecoder()
            let imageList = try decoder.decode([ImageItem].self, from: data)
            
            
            return imageList
            
        } catch {
            print("读取失败: \(error)")
            return nil
        }
    }
    
    private func writeImageItem(to plistPath: String, with newItem: ImageItem) -> Bool {
        let fileURL = URL(fileURLWithPath: plistPath)
        
        do {
            var imageList = readImageList(from: plistPath) ?? []
            // 检查imageList中是否已经存在具有相同id的ImageItem
            let exists = imageList.contains { $0.id == newItem.id }
            if !exists {
                // 如果不存在，才将newItem添加到imageList中
                imageList.append(newItem)
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .xml
                let data = try encoder.encode(imageList)
                try data.write(to: fileURL)
            } else {
                print("项目已存在，未添加")
            }
            return true
        } catch {
            print("写入失败: \(error)")
            return false
        }
    }

    // 查找代码里面匹配的字符串，闭包第一个参数是匹配到的字符串，第二个参数是匹配的文件路径
    private func searchForStrings(_ imageNameList: Set<String>, in directoryPath: String, matchFound: @escaping (String, String) -> Void) {
        //将图片名称转换成两种形式：".imageName", "\"imageName\""
//        let searchStrings = imageNameList.flatMap { imageName -> [String] in
//            return [".\(imageName)", "\"\(imageName)\""]
//        }
        let searchStrings = imageNameList.map { imageName -> String in
                imageName.lowercased().replacingOccurrences(of: "_", with: "")
            }
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        // 使用enumerator(at:includingPropertiesForKeys:options:errorHandler:)递归遍历
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: options, errorHandler: { (url, error) -> Bool in
            print("遍历错误: \(url): \(error)")
            return true // 继续遍历其他文件/目录
        }) else { return }

        for case let fileURL as URL in enumerator {
            guard let fileAttributes = try? fileURL.resourceValues(forKeys: Set(keys)),
                  fileAttributes.isRegularFile! else { continue }

            if fileURL.pathExtension == "swift" {
                // 读取并检查文件内容
                do {
//                    let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
//                    for searchString in searchStrings {
//                        if fileContents.range(of: searchString, options: .caseInsensitive) != nil {
//                            // 找到包含指定字符串的文件，执行相应的操作
//                            print("Found '\(searchString)' in file: \(fileURL.path)")
//                            matchFound(searchString, fileURL.path) // 执行闭包
//                        }
//                    }
                    let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
                     // 对文件内容进行同样的预处理：转换为小写并移除下划线
                     let processedFileContents = fileContents.lowercased().replacingOccurrences(of: "_", with: "")

                     for imageName in imageNameList {
                         // 对每个 imageName 进行同样的预处理后进行比较
                         let processedImageName = imageName.lowercased().replacingOccurrences(of: "_", with: "")
                         if processedFileContents.contains(processedImageName) {
                             // 找到匹配项，使用原始 imageName 调用 matchFound 闭包
                             matchFound(imageName, fileURL.path)
                         }
                     }
                } catch {
                    print("无法读取文件: \(fileURL.path). 错误: \(error)")
                }
            }
        }
    }
    
}
