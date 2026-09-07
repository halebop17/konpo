import Testing
@testable import Konpo

/// The disc-marker parsing that drives multi-disc album merging. The regex in
/// `FileTreeModel.discSuffixRegex` has to catch real-world disc naming without
/// swallowing volume numbers, years, or "No. 2" style titles — so both the
/// positive and the negative cases matter.
struct DiscSuffixTests {

    @Test("Parenthesised and bracketed disc markers are stripped", arguments: [
        ("Bob Marley - Legend (CD1)", "Bob Marley - Legend", "CD 1"),
        ("Bob Marley - Legend (CD 1)", "Bob Marley - Legend", "CD 1"),
        ("The Wall [Disc 2]", "The Wall", "Disc 2"),
        ("The Wall [Disk 2]", "The Wall", "Disk 2"),
        ("Live In Paris (DVD1)", "Live In Paris", "DVD 1"),
        ("Sandinista! (cd3)", "Sandinista!", "CD 3"),
    ])
    func parenthesised(name: String, base: String, label: String) {
        let result = FileTreeModel.discSuffix(name)
        #expect(result?.base == base)
        #expect(result?.label == label)
    }

    @Test("Bare and separator-joined disc markers are stripped", arguments: [
        ("Mellon Collie CD1", "Mellon Collie", "CD 1"),
        ("Mellon Collie - Disc 1", "Mellon Collie", "Disc 1"),
        ("Mellon Collie_CD2", "Mellon Collie", "CD 2"),
        ("Mellon Collie.disc3", "Mellon Collie", "Disc 3"),
        ("All Things Must Pass Disc 1 of 3", "All Things Must Pass", "Disc 1"),
    ])
    func bare(name: String, base: String, label: String) {
        let result = FileTreeModel.discSuffix(name)
        #expect(result?.base == base)
        #expect(result?.label == label)
    }

    /// The important half: names that merely *look* numeric must not be treated
    /// as discs, or unrelated albums would be merged into one.
    @Test("Non-disc trailing numbers are left alone", arguments: [
        "Best of, Vol. 2",
        "Symphony No. 2",
        "Album 1999",
        "Chapter 4",
        "Part 2",
        "Untitled",
        "Blonde on Blonde",
        "Vol 3",
    ])
    func notADisc(name: String) {
        #expect(FileTreeModel.discSuffix(name) == nil)
    }

    /// A bare disc folder name has no album base in front of it, so it is a disc
    /// *subfolder* (Album/CD1), not a sibling disc — `discSuffix` must decline it
    /// and leave it to `isDiscFolderName`.
    @Test("A bare disc name has no album base", arguments: ["CD1", "CD 1", "Disc 2", "disk3", "DVD1"])
    func bareDiscNameHasNoBase(name: String) {
        #expect(FileTreeModel.discSuffix(name) == nil)
    }
}

struct DiscFolderNameTests {

    @Test("Recognised disc subfolder names", arguments: [
        "CD1", "CD 1", "CD-01", "CD_2", "cd10",
        "Disc 2", "disc2", "Disk3", "disk 4",
        "DVD1", "dvd 2",
        "CD1 - Bonus Material",
    ])
    func recognised(name: String) {
        #expect(FileTreeModel.isDiscFolderName(name))
    }

    @Test("Folders that are not discs", arguments: [
        "Artwork", "Scans", "Bonus", "Extras",
        "CD", "Disc", "Discography", "Disko",
        "Covers", "Live",
    ])
    func notRecognised(name: String) {
        #expect(!FileTreeModel.isDiscFolderName(name))
    }
}

struct DiscLabelTests {

    @Test("Raw markers normalise to a clean header", arguments: [
        ("cd1", "CD 1"),
        ("CD 1", "CD 1"),
        ("CD-01", "CD 01"),
        ("disc2", "Disc 2"),
        ("Disc 2", "Disc 2"),
        ("disk3", "Disk 3"),
        ("dvd1", "DVD 1"),
        ("cd 10", "CD 10"),
    ])
    func normalise(raw: String, expected: String) {
        #expect(FileTreeModel.normalizeDiscLabel(raw) == expected)
    }
}
