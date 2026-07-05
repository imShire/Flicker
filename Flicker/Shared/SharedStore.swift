//
//  SharedStore.swift
//  Flicker
//
//  Shared between the container app and the Finder Sync extension.
//  Reads/writes the configured AppEntry list via a fixed file path.
//

import Foundation
import os

/// 配置读写。App 与 Finder Sync 扩展共享配置。
///
/// 使用 App Group 容器（~/Library/Group Containers/group.com.wangyanan.flicker/Flicker/）
/// 作为共享目录，避免扩展沙盒无法访问绝对路径的问题。首次启动时会从旧路径
///（~/Library/Application Support/Flicker/）迁移已有配置。
enum SharedStore {
    static let configFileName = "app_entries.json"
    static let menuSettingsFileName = "menu_settings.json"
    static let newFileSettingsFileName = "new_file_settings.json"
    static let appSupportSubdir = "Flicker"
    static let appGroupIdentifier = "group.com.wangyanan.flicker"
    private static let logger = Logger(subsystem: "com.wangyanan.flicker", category: "SharedStore")

    /// 真实用户主目录（不受沙盒容器重定向影响）。
    private static var realHomeDirectory: URL? {
        guard let pw = getpwuid(getuid()) else { return nil }
        return URL(fileURLWithFileSystemRepresentation: pw.pointee.pw_dir, isDirectory: true, relativeTo: nil)
    }

    /// 共享目录 URL。优先使用 App Group 容器，便于沙盒扩展共享。
    static var sharedDirectoryURL: URL? {
        let fm = FileManager.default

        // 优先使用 App Group 容器，主 App 与沙盒扩展均可访问。
        if let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let dir = containerURL.appendingPathComponent(appSupportSubdir, isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }

        // Fallback：旧路径（兼容未启用 App Group 的场景）。
        guard let home = realHomeDirectory else { return nil }
        let dir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(appSupportSubdir, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 旧版配置目录 URL（~/Library/Application Support/Flicker/）。
    private static var legacyDirectoryURL: URL? {
        guard let home = realHomeDirectory else { return nil }
        let dir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(appSupportSubdir, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 将旧路径下的配置迁移到 App Group 容器。
    /// 仅在 App Group 目录中不存在对应文件且旧目录存在文件时执行。
    static func migrateLegacyConfigIfNeeded() {
        let fm = FileManager.default

        guard let legacyDir = legacyDirectoryURL,
              let sharedDir = sharedDirectoryURL else { return }

        let fileNames = [configFileName, menuSettingsFileName, newFileSettingsFileName]
        var migratedAny = false

        for fileName in fileNames {
            let legacyURL = legacyDir.appendingPathComponent(fileName, isDirectory: false)
            let sharedURL = sharedDir.appendingPathComponent(fileName, isDirectory: false)

            guard fm.fileExists(atPath: legacyURL.path),
                  !fm.fileExists(atPath: sharedURL.path) else { continue }

            do {
                try fm.copyItem(at: legacyURL, to: sharedURL)
                migratedAny = true
                logger.info("migrated \(fileName, privacy: .public) to app group container")
            } catch {
                logger.error("migrate \(fileName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if migratedAny {
            logger.info("legacy config migration finished")
        }
    }

    /// 共享配置文件 URL。
    static var configFileURL: URL? {
        sharedDirectoryURL?.appendingPathComponent(configFileName, isDirectory: false)
    }

    /// 菜单设置文件 URL。
    static var menuSettingsFileURL: URL? {
        sharedDirectoryURL?.appendingPathComponent(menuSettingsFileName, isDirectory: false)
    }
    
    /// 新建文件设置文件 URL。
    static var newFileSettingsFileURL: URL? {
        sharedDirectoryURL?.appendingPathComponent(newFileSettingsFileName, isDirectory: false)
    }

    /// 读取应用列表。
    static func loadEntries() -> [AppEntry] {
        guard let url = configFileURL,
              let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([AppEntry].self, from: data)
        } catch {
            logger.error("loadEntries decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// 写入应用列表。
    @discardableResult
    static func saveEntries(_ entries: [AppEntry]) -> Bool {
        guard let url = configFileURL else { return false }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            logger.error("saveEntries failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Menu Settings

    /// 读取菜单设置。文件不存在时返回默认值。
    static func loadMenuSettings() -> MenuSettings {
        guard let url = menuSettingsFileURL,
              let data = try? Data(contentsOf: url) else { return .defaults }
        do {
            return try JSONDecoder().decode(MenuSettings.self, from: data)
        } catch {
            logger.error("loadMenuSettings decode failed: \(error.localizedDescription, privacy: .public)")
            return .defaults
        }
    }

    /// 写入菜单设置。
    @discardableResult
    static func saveMenuSettings(_ settings: MenuSettings) -> Bool {
        guard let url = menuSettingsFileURL else { return false }
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            logger.error("saveMenuSettings failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    // MARK: - New File Settings
    
    /// 读取新建文件设置。文件不存在时返回默认值。
    static func loadNewFileSettings() -> NewFileSettings {
        guard let url = newFileSettingsFileURL,
              let data = try? Data(contentsOf: url) else { return .defaults }
        do {
            return try JSONDecoder().decode(NewFileSettings.self, from: data)
        } catch {
            logger.error("loadNewFileSettings decode failed: \(error.localizedDescription, privacy: .public)")
            return .defaults
        }
    }
    
    /// 写入新建文件设置。
    @discardableResult
    static func saveNewFileSettings(_ settings: NewFileSettings) -> Bool {
        guard let url = newFileSettingsFileURL else { return false }
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            logger.error("saveNewFileSettings failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
