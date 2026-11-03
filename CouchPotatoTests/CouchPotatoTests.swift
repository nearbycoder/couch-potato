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

    func testPublishedSeriesCatalogDecodes() throws {
        // The shape scripts/build_catalog.py writes to docs/catalog/v1/<service>.json.
        let json = """
        [{"id":82,"url":"https://www.tvmaze.com/shows/82/game-of-thrones","name":"Game of Thrones","type":"Scripted","language":"English","genres":["Drama","Fantasy"],"status":"Ended","averageRuntime":61,"premiered":"2011-04-17","rating":{"average":8.9},"weight":99,"network":{"id":8,"name":"HBO"},"externals":{"imdb":"tt0944947"},"image":{"medium":"https://static.tvmaze.com/m.jpg","original":"https://static.tvmaze.com/o.jpg"},"summary":"Seven noble families fight for control."},
         {"id":1,"name":"Bare","rating":{"average":null},"image":{"medium":"https://static.tvmaze.com/b.jpg"},"webChannel":{"id":1,"name":"Netflix"}}]
        """
        let shows = try JSONDecoder().decode([TVMShow].self, from: Data(json.utf8))
        let titles = shows.map(\.catalogTitle)
        XCTAssertEqual(titles.map(\.ref.key), ["tvmaze-tv-82", "tvmaze-tv-1"])
        XCTAssertEqual(titles[0].providers, [.hbo])
        XCTAssertEqual(titles[0].year, 2011)
        XCTAssertEqual(titles[0].popularity, 99)
        XCTAssertEqual(titles[1].providers, [.netflix])
        XCTAssertEqual(titles[1].posterURL?.lastPathComponent, "b.jpg")
    }

    private func sample(_ name: String, year: Int, genres: [String], score: Double?) -> CatalogTitle {
        CatalogTitle(ref: TitleRef(source: .tvmaze, kind: .tv, id: name), name: name,
                     year: year, releaseDate: DateParsing.date("\(year)-06-01"), genres: genres, score: score)
    }

    func testTitleFilterNarrowsAndSorts() {
        let titles = [
            sample("Bravo", year: 2015, genres: ["Drama"], score: 7.5),
            sample("alpha", year: 2023, genres: ["Science-Fiction"], score: 8.4),
            sample("Charlie", year: 1988, genres: ["Comedy"], score: nil),
            sample("Delta", year: 2021, genres: ["Sci-Fi & Fantasy"], score: 6.1),
        ]
        // Popular keeps the incoming order.
        XCTAssertEqual(TitleFilter().apply(titles).map(\.name), ["Bravo", "alpha", "Charlie", "Delta"])
        XCTAssertEqual(TitleFilter(years: .y2020s).apply(titles).map(\.name), ["alpha", "Delta"])
        XCTAssertEqual(TitleFilter(years: .older).apply(titles).map(\.name), ["Charlie"])
        XCTAssertEqual(TitleFilter(genre: .scifi).apply(titles).map(\.name), ["alpha", "Delta"])
        XCTAssertEqual(TitleFilter(minRating: 7).apply(titles).map(\.name), ["Bravo", "alpha"])
        XCTAssertEqual(TitleFilter(sort: .newest).apply(titles).map(\.name), ["alpha", "Delta", "Bravo", "Charlie"])
        XCTAssertEqual(TitleFilter(sort: .rating).apply(titles).map(\.name), ["alpha", "Bravo", "Delta", "Charlie"])
        XCTAssertEqual(TitleFilter(sort: .title).apply(titles).map(\.name), ["alpha", "Bravo", "Charlie", "Delta"])
    }

    func testTitleFilterBuildsTMDBQueries() throws {
        let filter = TitleFilter(sort: .newest, years: .y2010s, genre: .horror, minRating: 7)
        let movie = try XCTUnwrap(filter.tmdbQuery(for: .movie))
        XCTAssertEqual(movie.sort, "primary_release_date.desc")
        XCTAssertEqual(movie.genres, [27])
        XCTAssertEqual(movie.extra["primary_release_date.gte"], "2010-01-01")
        XCTAssertEqual(movie.extra["primary_release_date.lte"], "2019-12-31")
        XCTAssertEqual(movie.extra["vote_average.gte"], "7")
        // TMDB has no horror genre for series, so the TV half is skipped.
        XCTAssertNil(filter.tmdbQuery(for: .tv))
        XCTAssertEqual(TitleFilter(sort: .title).tmdbQuery(for: .tv)?.sort, "name.asc")
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
        XCTAssertEqual(CouchRank.levels.first?.name, "Newcomer")
        XCTAssertEqual(CouchRank(titles: [], nights: []).level.name, "Newcomer")
    }
}
