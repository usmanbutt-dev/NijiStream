// NijiStream — Reference Extension (Example/Test)
//
// This is a sample extension that demonstrates the extension API contract.
// It uses a mock data pattern (returns hardcoded data) so it works without
// any external dependencies — useful for testing the extension engine.
//
// Real extensions would use http.get() to fetch data from anime sites
// and parseHtml() to extract information from the returned HTML.

const manifest = {
  id: "com.nijistream.example",
  name: "Example Source",
  version: "1.0.0",
  lang: "en",
  author: "nijistream",
  description: "A reference extension for testing the extension engine. Returns mock data.",
  icon: null,
  nsfw: false
};

class AnimeSource {
  // ── Search (REQUIRED) ──
  async search(query, page) {
    log("Searching for: " + query + ", page: " + page);

    // Simulate search results based on query
    const mockResults = [
      {
        id: "naruto",
        title: "Naruto Shippuden",
        cover: "https://cdn.myanimelist.net/images/anime/5/17407.jpg",
        url: "/anime/naruto-shippuden"
      },
      {
        id: "one-piece",
        title: "One Piece",
        cover: "https://cdn.myanimelist.net/images/anime/6/73245.jpg",
        url: "/anime/one-piece"
      },
      {
        id: "aot",
        title: "Attack on Titan",
        cover: "https://cdn.myanimelist.net/images/anime/10/47347.jpg",
        url: "/anime/attack-on-titan"
      },
      {
        id: "demon-slayer",
        title: "Demon Slayer: Kimetsu no Yaiba",
        cover: "https://cdn.myanimelist.net/images/anime/1286/99889.jpg",
        url: "/anime/demon-slayer"
      },
      {
        id: "jjk",
        title: "Jujutsu Kaisen",
        cover: "https://cdn.myanimelist.net/images/anime/1171/109222.jpg",
        url: "/anime/jujutsu-kaisen"
      }
    ];

    // Filter by query (case-insensitive)
    const lowerQuery = query.toLowerCase();
    const filtered = mockResults.filter(function(item) {
      return item.title.toLowerCase().indexOf(lowerQuery) !== -1;
    });

    return {
      hasNextPage: false,
      results: page === 1 ? (filtered.length > 0 ? filtered : mockResults) : []
    };
  }

  // ── Get Detail (REQUIRED) ──
  async getDetail(animeId) {
    log("Getting detail for: " + animeId);

    const details = {
      "naruto": {
        title: "Naruto Shippuden",
        cover: "https://cdn.myanimelist.net/images/anime/5/17407.jpg",
        banner: null,
        synopsis: "It has been two and a half years since Naruto Uzumaki left Konohagakure, the Hidden Leaf Village, for intense training following events which fueled his desire to be stronger.",
        genres: ["Action", "Adventure", "Fantasy"],
        status: "completed",
        episodes: [
          { number: 1, title: "Homecoming", url: "/watch/naruto/1" },
          { number: 2, title: "The Akatsuki Makes Its Move", url: "/watch/naruto/2" },
          { number: 3, title: "The Results of Training", url: "/watch/naruto/3" },
          { number: 4, title: "The Jinchuriki of the Sand", url: "/watch/naruto/4" },
          { number: 5, title: "The Kazekage Stands Tall", url: "/watch/naruto/5" }
        ]
      },
      "one-piece": {
        title: "One Piece",
        cover: "https://cdn.myanimelist.net/images/anime/6/73245.jpg",
        banner: null,
        synopsis: "Gol D. Roger was known as the 'Pirate King,' the strongest and most infamous being to have sailed the Grand Line.",
        genres: ["Action", "Adventure", "Comedy"],
        status: "airing",
        episodes: [
          { number: 1, title: "I'm Luffy! The Man Who's Gonna Be King of the Pirates!", url: "/watch/one-piece/1" },
          { number: 2, title: "Enter the Great Swordsman! Pirate Hunter Roronoa Zoro!", url: "/watch/one-piece/2" },
          { number: 3, title: "Morgan versus Luffy! Who's the Mysterious Pretty Girl?", url: "/watch/one-piece/3" }
        ]
      }
    };

    // Return details for known anime, or a default
    const detail = details[animeId];
    if (detail) return detail;

    return {
      title: "Unknown Anime (" + animeId + ")",
      cover: null,
      synopsis: "No details available for this anime.",
      genres: [],
      status: "unknown",
      episodes: [
        { number: 1, title: "Episode 1", url: "/watch/" + animeId + "/1" }
      ]
    };
  }

  // ── Get Video Sources (REQUIRED) ──
  async getVideoSources(episodeUrl) {
    log("Getting video sources for: " + episodeUrl);

    // Return mock video sources
    // In a real extension, you'd fetch the page at episodeUrl,
    // parse it for video player embed URLs, and extract the
    // actual streaming URLs.
    return {
      sources: [
        {
          url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
          quality: "auto",
          type: "hls"
        }
      ],
      subtitles: []
    };
  }

  // ── Get Latest (OPTIONAL) ──
  async getLatest(page) {
    log("Getting latest, page: " + page);
    return this.search("", page);
  }

  // ── Get Popular (OPTIONAL) ──
  async getPopular(page) {
    log("Getting popular, page: " + page);
    return this.search("", page);
  }
}
