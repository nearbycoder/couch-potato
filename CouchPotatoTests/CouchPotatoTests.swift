import XCTest
@testable import CouchPotato

final class CouchPotatoTests: XCTestCase {
    func testTitleRefRoundTripsThroughKey() {
        let ref = TitleRef(source: .tmdb, kind: .tv, id: "1396")
        XCTAssertEqual(ref.key, "tmdb-tv-1396")
        XCTAssertEqual(TitleRef(key: ref.key), ref)
        XCTAssertNil(TitleRef(key: "nope"))
    }

    func testProviderMatchingCoversNetworksAndStreamers() {
        XCTAssertEqual(Provider.matching(name: "Apple TV"), .apple)
        XCTAssertEqual(Provider.matching(name: "Netflix"), .netflix)
        XCTAssertEqual(Provider.matching(name: "FX"), .hulu)
        XCTAssertEqual(Provider.matching(name: "HBO Max"), .hbo)
        XCTAssertEqual(Provider.matching(name: "Paramount+ with Showtime"), .paramount)
        XCTAssertEqual(Provider.with(tmdbID: 337), .disney)
        XCTAssertNil(Provider.matching(name: "Some Local Channel"))
    }

    func testITunesArtworkIsUpscaled() {
        let url = ITunesClient.upscale("https://is1-ssl.mzstatic.com/image/thumb/Video211/v4/x/2000x3000_Verity.jpg/115x170bb.png")
        XCTAssertEqual(url?.lastPathComponent, "600x900bb.jpg")
    }

    func testHTMLStripping() {
        XCTAssertEqual("<p>Mark &amp; <b>Helly</b></p>".strippingHTML, "Mark & Helly")
    }

    func testTMDBWatchProvidersBecomeOffers() throws {
        let json = """
        {"results":{"US":{"link":"https://www.themoviedb.org/movie/1/watch","flatrate":[{"provider_id":8,"provider_name":"Netflix","logo_path":"/n.jpg","display_priority":1},{"provider_id":1796,"provider_name":"Netflix basic with Ads","logo_path":"/n2.jpg","display_priority":2}],"rent":[{"provider_id":2,"provider_name":"Apple TV","logo_path":"/a.jpg","display_priority":1}],"buy":[{"provider_id":999,"provider_name":"Spud Store","logo_path":null,"display_priority":3}]}}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let providers = try decoder.decode(TMDBWatchProviders.self, from: Data(json.utf8))
        let availability = providers.availability(region: "US")
        XCTAssertEqual(availability.offers(.stream).map(\.provider), [.netflix])
        XCTAssertEqual(availability.offers(.rent).map(\.provider), [.appleStore])
        XCTAssertEqual(availability.offers(.buy).first?.provider.name, "Spud Store")
        XCTAssertNotNil(availability.link)
    }

    func testCouchRankLevelsUp() {
        XCTAssertEqual(CouchRank.levels.first?.name, "Raw Spud")
        XCTAssertEqual(CouchRank(titles: [], nights: []).level.name, "Raw Spud")
    }
}
