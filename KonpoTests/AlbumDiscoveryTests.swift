import Testing
import Foundation
@testable import Konpo

/// `FileTreeModel.albumFolders(under:)` turns a directory tree into the album
/// grid's contents. The rules it encodes — a folder with audio is an album, disc
/// subfolders collapse, sibling "(CD1)/(CD2)" folders merge, everything else is
/// a branch to recurse into — are the kind of thing that is easy to regress.
struct AlbumDiscoveryTests {

    @Test("A folder of audio files is one single-disc album")
    func flatAlbum() throws {
        let tree = try TempTree([
            "Kind of Blue/01 So What.flac",
            "Kind of Blue/02 Freddie Freeloader.flac",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.url("Kind of Blue"))
        #expect(albums.count == 1)
        #expect(albums.first?.name == "Kind of Blue")
        #expect(albums.first?.discs.count == 1)
        #expect(albums.first?.discs.first?.label == nil)
        #expect(albums.first?.isMultiDisc == false)
        #expect(albums.first?.trackURLs.count == 2)
    }

    @Test("Tracks within a disc sort naturally, not lexically")
    func naturalTrackOrder() throws {
        let tree = try TempTree([
            "Album/1 One.mp3", "Album/2 Two.mp3", "Album/10 Ten.mp3", "Album/11 Eleven.mp3",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.root)
        let names = albums.first?.trackURLs.map(\.lastPathComponent)
        #expect(names == ["1 One.mp3", "2 Two.mp3", "10 Ten.mp3", "11 Eleven.mp3"])
    }

    @Test("Non-audio files are ignored")
    func ignoresNonAudio() throws {
        let tree = try TempTree([
            "Album/01 Track.flac",
            "Album/cover.jpg", "Album/notes.txt", "Album/album.cue", "Album/rip.log",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.root)
        #expect(albums.first?.trackURLs.count == 1)
    }

    @Test("A folder with no audio anywhere yields no albums")
    func emptyTree() throws {
        let tree = try TempTree(["Scans/front.jpg", "Empty"])
        #expect(FileTreeModel.albumFolders(under: tree.root).isEmpty)
    }

    @Test("A genre branch yields one album per child, sorted by name")
    func branchFolder() throws {
        let tree = try TempTree([
            "Rock/Zeppelin IV/01 a.flac",
            "Rock/Abbey Road/01 b.flac",
            "Rock/Nevermind/01 c.flac",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.url("Rock"))
        #expect(albums.map(\.name) == ["Abbey Road", "Nevermind", "Zeppelin IV"])
        #expect(albums.allSatisfy { $0.discs.count == 1 })
    }

    @Test("Albums are found several levels down")
    func deepNesting() throws {
        let tree = try TempTree([
            "Music/Rock/Pink Floyd/Animals/01 Pigs.flac",
            "Music/Jazz/Miles Davis/Milestones/01 Dr Jekyll.flac",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.root)
        #expect(albums.map(\.name) == ["Animals", "Milestones"])
    }

    // MARK: - Multi-disc

    @Test("Disc subfolders collapse into one multi-disc album")
    func discSubfolders() throws {
        let tree = try TempTree([
            "The Wall/CD1/01 In the Flesh.flac",
            "The Wall/CD1/02 The Thin Ice.flac",
            "The Wall/CD2/01 Hey You.flac",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.url("The Wall"))
        #expect(albums.count == 1)
        let album = try #require(albums.first)
        #expect(album.name == "The Wall")
        #expect(album.isMultiDisc)
        #expect(album.discs.map(\.label) == ["CD 1", "CD 2"])
        #expect(album.discs.map(\.trackURLs.count) == [2, 1])
        // Playback order is disc-then-track across the whole album.
        #expect(album.trackURLs.count == 3)
        #expect(album.trackURLs.first?.lastPathComponent == "01 In the Flesh.flac")
        #expect(album.trackURLs.last?.lastPathComponent == "01 Hey You.flac")
    }

    @Test("Disc subfolders sort naturally past nine")
    func manyDiscs() throws {
        let tree = try TempTree((1...11).map { "Box Set/CD\($0)/01 track.flac" })
        let albums = FileTreeModel.albumFolders(under: tree.url("Box Set"))
        let album = try #require(albums.first)
        #expect(album.discs.map(\.label) == (1...11).map { "CD \($0)" })
    }

    @Test("Sibling (CD1)/(CD2) folders merge into one album under the shared base")
    func siblingDiscFolders() throws {
        let tree = try TempTree([
            "Sandinista! (CD1)/01 a.flac",
            "Sandinista! (CD2)/01 b.flac",
            "Sandinista! (CD3)/01 c.flac",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.root)
        #expect(albums.count == 1)
        let album = try #require(albums.first)
        #expect(album.name == "Sandinista!")
        #expect(album.discs.map(\.label) == ["CD 1", "CD 2", "CD 3"])
    }

    @Test("A lone (CD1) with no sibling keeps its own name and shows no disc header")
    func loneDiscFolder() throws {
        let tree = try TempTree(["Greatest Hits (CD1)/01 a.flac"])
        let albums = FileTreeModel.albumFolders(under: tree.root)
        #expect(albums.count == 1)
        let album = try #require(albums.first)
        #expect(album.name == "Greatest Hits (CD1)")
        #expect(album.isMultiDisc == false)
        #expect(album.discs.first?.label == nil)
    }

    @Test("Sibling discs merge alongside unrelated albums in the same branch")
    func mixedBranch() throws {
        let tree = try TempTree([
            "Rock/Sandinista! (CD1)/01 a.flac",
            "Rock/Sandinista! (CD2)/01 b.flac",
            "Rock/Nevermind/01 c.flac",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.url("Rock"))
        #expect(albums.map(\.name) == ["Nevermind", "Sandinista!"])
        #expect(albums.first { $0.name == "Sandinista!" }?.discs.count == 2)
        #expect(albums.first { $0.name == "Nevermind" }?.discs.count == 1)
    }

    @Test("Two different multi-disc albums in one branch stay separate")
    func twoSiblingGroups() throws {
        let tree = try TempTree([
            "Rock/Album A (CD1)/01 a.flac", "Rock/Album A (CD2)/01 b.flac",
            "Rock/Album B (CD1)/01 c.flac", "Rock/Album B (CD2)/01 d.flac",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.url("Rock"))
        #expect(albums.map(\.name) == ["Album A", "Album B"])
        #expect(albums.allSatisfy { $0.discs.count == 2 })
    }

    @Test("A folder with its own audio is an album even when it has subfolders")
    func audioWinsOverSubfolders() throws {
        let tree = try TempTree([
            "Album/01 track.flac",
            "Album/Scans/front.jpg",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.url("Album"))
        #expect(albums.count == 1)
        #expect(albums.first?.discs.count == 1)
    }

    @Test("Disc folders mixed with a non-disc audio folder are not collapsed")
    func partialDiscFoldersStaySeparate() throws {
        // Only *all*-disc children collapse; a stray "Bonus" folder means these
        // are ordinary sibling albums, not one multi-disc album.
        let tree = try TempTree([
            "Set/CD1/01 a.flac",
            "Set/CD2/01 b.flac",
            "Set/Bonus/01 c.flac",
        ])
        let albums = FileTreeModel.albumFolders(under: tree.url("Set"))
        #expect(albums.count == 3)
        #expect(albums.map(\.name) == ["Bonus", "CD1", "CD2"])
    }

    // MARK: - Robustness

    /// `scanDirectory` classifies entries with `.isDirectoryKey`, which reports
    /// `false` for a symlink (it does not resolve them). Symlinks are therefore
    /// neither recursed into nor treated as audio — which is what makes a
    /// symlink loop pointing back at an ancestor harmless. Pinning this down,
    /// because the walk has no explicit cycle guard and relies on it.
    @Test("Symlink loops are unreachable because symlinks are never followed")
    func symlinkLoopIsUnreachable() throws {
        let tree = try TempTree(["Music/Branch/Album/01 track.flac"])
        try tree.link("Music/Branch/loop", to: "Music")
        let albums = FileTreeModel.albumFolders(under: tree.url("Music"))
        #expect(albums.count == 1)
        #expect(albums.first?.name == "Album")
    }

    @Test("A symlinked album folder is skipped rather than listed twice")
    func symlinkedAlbumIsSkipped() throws {
        let tree = try TempTree(["Music/Real Album/01 track.flac"])
        try tree.link("Music/Alias", to: "Music/Real Album")
        let albums = FileTreeModel.albumFolders(under: tree.url("Music"))
        #expect(albums.map(\.name) == ["Real Album"])
    }

    @Test("Deeply nested trees are walked without overflowing the stack")
    func veryDeepTree() throws {
        let deep = (1...80).map { "d\($0)" }.joined(separator: "/")
        let tree = try TempTree(["\(deep)/01 track.flac"])
        let albums = FileTreeModel.albumFolders(under: tree.root)
        #expect(albums.count == 1)
    }
}

/// The plain (non-album) directory listing helpers.
struct FileEnumerationTests {

    @Test("audioFiles lists only audio in one directory, naturally sorted")
    func audioFiles() throws {
        let tree = try TempTree([
            "Album/10 j.mp3", "Album/2 b.mp3", "Album/1 a.mp3",
            "Album/cover.jpg", "Album/Sub/01 nested.mp3",
        ])
        let files = FileTreeModel.audioFiles(in: tree.url("Album"))
        #expect(files.map { $0.url.lastPathComponent } == ["1 a.mp3", "2 b.mp3", "10 j.mp3"])
    }

    @Test("audioFilesRecursive descends into subfolders")
    func recursive() throws {
        let tree = try TempTree([
            "Album/01 a.mp3", "Album/CD2/01 b.mp3", "Album/CD2/Deeper/01 c.mp3",
            "Album/cover.jpg",
        ])
        let files = FileTreeModel.audioFilesRecursive(in: tree.url("Album"))
        #expect(files.count == 3)
    }

    @Test("subdirectories lists only directories")
    func subdirs() throws {
        let tree = try TempTree(["Root/A/x.mp3", "Root/B/x.mp3", "Root/loose.mp3"])
        let dirs = FileTreeModel.subdirectories(of: tree.url("Root"))
        #expect(dirs.map(\.lastPathComponent) == ["A", "B"])
    }

    @Test("hasSubdirectory distinguishes album folders from branches")
    func leafDetection() throws {
        let tree = try TempTree(["Branch/Album/01 a.mp3"])
        #expect(FileTreeModel.hasSubdirectory(tree.url("Branch")))
        #expect(!FileTreeModel.hasSubdirectory(tree.url("Branch/Album")))
    }
}
