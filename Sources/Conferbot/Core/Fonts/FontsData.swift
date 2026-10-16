//
//  FontsData.swift
//  Conferbot
//
//  The owner font catalog and the widget themes' Google Fonts queries.
//  Generated from the React Native SDK's src/core/fonts.data.ts (itself
//  copied from conferbot-widget src/ts/fonts/catalog.ts between its
//  FONTS:BEGIN / FONTS:END markers and src/ts/theme/registry.ts). Don't edit
//  by hand; OwnerFontTests fails when it drifts from RN's.
//

import Foundation

extension OwnerFont {
    /// The dashboard's font picker, in its order.
    public static let catalog: [CatalogFont] = [
        CatalogFont(id: "inter", label: "Inter", family: "Inter", category: "sans", stack: "'Inter', sans-serif", google: "Inter:wght@400;500;600;700"),
        CatalogFont(id: "manrope", label: "Manrope", family: "Manrope", category: "sans", stack: "'Manrope', sans-serif", google: "Manrope:wght@400;500;600;700"),
        CatalogFont(id: "plus-jakarta-sans", label: "Plus Jakarta Sans", family: "Plus Jakarta Sans", category: "sans", stack: "'Plus Jakarta Sans', sans-serif", google: "Plus+Jakarta+Sans:wght@400;500;600;700"),
        CatalogFont(id: "dm-sans", label: "DM Sans", family: "DM Sans", category: "sans", stack: "'DM Sans', sans-serif", google: "DM+Sans:wght@400;500;600;700"),
        CatalogFont(id: "outfit", label: "Outfit", family: "Outfit", category: "sans", stack: "'Outfit', sans-serif", google: "Outfit:wght@400;500;600;700"),
        CatalogFont(id: "poppins", label: "Poppins", family: "Poppins", category: "sans", stack: "'Poppins', sans-serif", google: "Poppins:wght@400;500;600;700"),
        CatalogFont(id: "figtree", label: "Figtree", family: "Figtree", category: "sans", stack: "'Figtree', sans-serif", google: "Figtree:wght@400;500;600;700"),
        CatalogFont(id: "onest", label: "Onest", family: "Onest", category: "sans", stack: "'Onest', sans-serif", google: "Onest:wght@400;500;600;700"),
        CatalogFont(id: "geist", label: "Geist", family: "Geist", category: "sans", stack: "'Geist', sans-serif", google: "Geist:wght@400;500;600;700"),
        CatalogFont(id: "nunito", label: "Nunito", family: "Nunito", category: "rounded", stack: "'Nunito', sans-serif", google: "Nunito:wght@400;500;600;700"),
        CatalogFont(id: "quicksand", label: "Quicksand", family: "Quicksand", category: "rounded", stack: "'Quicksand', sans-serif", google: "Quicksand:wght@400;500;600;700"),
        CatalogFont(id: "fredoka", label: "Fredoka", family: "Fredoka", category: "rounded", stack: "'Fredoka', sans-serif", google: "Fredoka:wght@400;500;600;700"),
        CatalogFont(id: "baloo-2", label: "Baloo 2", family: "Baloo 2", category: "rounded", stack: "'Baloo 2', sans-serif", google: "Baloo+2:wght@400;500;600;700"),
        CatalogFont(id: "varela-round", label: "Varela Round", family: "Varela Round", category: "rounded", stack: "'Varela Round', sans-serif", google: "Varela+Round"),
        CatalogFont(id: "m-plus-rounded-1c", label: "M PLUS Rounded 1c", family: "M PLUS Rounded 1c", category: "rounded", stack: "'M PLUS Rounded 1c', sans-serif", google: "M+PLUS+Rounded+1c:wght@400;500;700"),
        CatalogFont(id: "playfair-display", label: "Playfair Display", family: "Playfair Display", category: "serif", stack: "'Playfair Display', serif", google: "Playfair+Display:wght@400;500;600;700"),
        CatalogFont(id: "fraunces", label: "Fraunces", family: "Fraunces", category: "serif", stack: "'Fraunces', serif", google: "Fraunces:wght@400;500;600;700"),
        CatalogFont(id: "cormorant-garamond", label: "Cormorant Garamond", family: "Cormorant Garamond", category: "serif", stack: "'Cormorant Garamond', serif", google: "Cormorant+Garamond:wght@400;500;600;700"),
        CatalogFont(id: "lora", label: "Lora", family: "Lora", category: "serif", stack: "'Lora', serif", google: "Lora:wght@400;500;600;700"),
        CatalogFont(id: "libre-baskerville", label: "Libre Baskerville", family: "Libre Baskerville", category: "serif", stack: "'Libre Baskerville', serif", google: "Libre+Baskerville:wght@400;700"),
        CatalogFont(id: "dm-serif-display", label: "DM Serif Display", family: "DM Serif Display", category: "serif", stack: "'DM Serif Display', serif", google: "DM+Serif+Display"),
        CatalogFont(id: "jetbrains-mono", label: "JetBrains Mono", family: "JetBrains Mono", category: "mono", stack: "'JetBrains Mono', monospace", google: "JetBrains+Mono:wght@400;500;600;700"),
        CatalogFont(id: "space-grotesk", label: "Space Grotesk", family: "Space Grotesk", category: "mono", stack: "'Space Grotesk', sans-serif", google: "Space+Grotesk:wght@400;500;600;700"),
        CatalogFont(id: "ibm-plex-sans", label: "IBM Plex Sans", family: "IBM Plex Sans", category: "mono", stack: "'IBM Plex Sans', sans-serif", google: "IBM+Plex+Sans:wght@400;500;600;700"),
        CatalogFont(id: "ibm-plex-mono", label: "IBM Plex Mono", family: "IBM Plex Mono", category: "mono", stack: "'IBM Plex Mono', monospace", google: "IBM+Plex+Mono:wght@400;500;600;700"),
        CatalogFont(id: "space-mono", label: "Space Mono", family: "Space Mono", category: "mono", stack: "'Space Mono', monospace", google: "Space+Mono:wght@400;700"),
        CatalogFont(id: "bricolage-grotesque", label: "Bricolage Grotesque", family: "Bricolage Grotesque", category: "display", stack: "'Bricolage Grotesque', sans-serif", google: "Bricolage+Grotesque:wght@400;500;600;700"),
        CatalogFont(id: "syne", label: "Syne", family: "Syne", category: "display", stack: "'Syne', sans-serif", google: "Syne:wght@400;500;600;700"),
        CatalogFont(id: "righteous", label: "Righteous", family: "Righteous", category: "display", stack: "'Righteous', sans-serif", google: "Righteous"),
        CatalogFont(id: "pacifico", label: "Pacifico", family: "Pacifico", category: "display", stack: "'Pacifico', cursive", google: "Pacifico"),
        CatalogFont(id: "caveat", label: "Caveat", family: "Caveat", category: "display", stack: "'Caveat', cursive", google: "Caveat:wght@400;500;600;700"),
        CatalogFont(id: "patrick-hand", label: "Patrick Hand", family: "Patrick Hand", category: "display", stack: "'Patrick Hand', cursive", google: "Patrick+Hand"),
        CatalogFont(id: "press-start-2p", label: "Press Start 2P", family: "Press Start 2P", category: "display", stack: "'Press Start 2P', monospace", google: "Press+Start+2P"),
        CatalogFont(id: "bungee", label: "Bungee", family: "Bungee", category: "display", stack: "'Bungee', sans-serif", google: "Bungee"),
        CatalogFont(id: "system-ui", label: "System UI", family: "system-ui", category: "system", stack: "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif", google: nil),
        CatalogFont(id: "arial", label: "Arial", family: "Arial", category: "system", stack: "Arial, Helvetica, sans-serif", google: nil),
        CatalogFont(id: "helvetica", label: "Helvetica", family: "Helvetica", category: "system", stack: "Helvetica, Arial, sans-serif", google: nil),
        CatalogFont(id: "georgia", label: "Georgia", family: "Georgia", category: "system", stack: "Georgia, 'Times New Roman', serif", google: nil),
        CatalogFont(id: "verdana", label: "Verdana", family: "Verdana", category: "system", stack: "Verdana, Geneva, sans-serif", google: nil),
        CatalogFont(id: "trebuchet", label: "Trebuchet MS", family: "Trebuchet MS", category: "system", stack: "'Trebuchet MS', Helvetica, sans-serif", google: nil),
    ]

    /// Theme font family -> its Google Fonts css2 "family=" query.
    public static let themeFontQueries: [String: String] = [
        "Inter": "Inter:wght@400;500;600;700",
        "Manrope": "Manrope:wght@400;500;600;700",
        "Fredoka": "Fredoka:wght@400;500;600;700",
        "VT323": "VT323",
        "Nunito": "Nunito:wght@400;600;700;800",
        "Fraunces": "Fraunces:opsz,wght@9..144,400;9..144,500;9..144,600;9..144,700",
        "JetBrains Mono": "JetBrains+Mono:wght@400;500;700",
        "Plus Jakarta Sans": "Plus+Jakarta+Sans:wght@400;500;600;700;800",
        "Space Grotesk": "Space+Grotesk:wght@400;500;600;700",
        "Quicksand": "Quicksand:wght@400;500;600;700",
        "Orbitron": "Orbitron:wght@500;600;700",
        "Patrick Hand": "Patrick+Hand",
        "Cormorant Garamond": "Cormorant+Garamond:wght@500;600;700",
        "Baloo 2": "Baloo+2:wght@400;500;600;700;800",
        "Lora": "Lora:wght@500;600;700",
        "Bangers": "Bangers",
        "Press Start 2P": "Press+Start+2P",
        "Righteous": "Righteous",
        "Unbounded": "Unbounded:wght@500;600;700",
        "Bungee": "Bungee",
        "Permanent Marker": "Permanent+Marker",
        "Cabin Sketch": "Cabin+Sketch:wght@400;700",
        "Chewy": "Chewy",
        "Chakra Petch": "Chakra+Petch:wght@400;500;600;700",
        "Exo 2": "Exo+2:wght@400;500;600;700",
    ]
}
