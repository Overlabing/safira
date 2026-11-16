// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// The site of a web address: its host's registrable domain (eTLD+1), letter case ignored, so that `mail.google.com`
/// and `google.com` are one site while `foo.github.io` and `bar.github.io` are two. An IP address, a host with a single
/// label (`localhost`) and a host that is itself a public suffix are their own site.
public struct RegistrableDomain: Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public var description: String { value }

    /// Nil for an address that is not an http or https address with a host.
    public init?(_ url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return nil }
        value = Self.registrableDomain(of: host)
    }

    private static func registrableDomain(of host: String) -> String {
        if host.contains(":") || isIPv4(host) { return host }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1 else { return host }
        // The longest listed suffix wins; an unlisted one is the last label, the list's default rule.
        let suffixLength = (2..<labels.count + 1).reversed()
            .first { PublicSuffixes.multiLabel.contains(labels.suffix($0).joined(separator: ".")) } ?? 1
        guard labels.count > suffixLength else { return host }
        return labels.suffix(suffixLength + 1).joined(separator: ".")
    }

    private static func isIPv4(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count == 4 && labels.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }
}

/// The public suffixes of more than one label that Safira knows, taken from the Public Suffix List
/// (publicsuffix.org): the second-level domains of common country codes, and the hosting services whose subdomains
/// belong to different owners. A suffix of one label needs no entry. The list is partial and ships with the app, so
/// nothing is fetched.
enum PublicSuffixes {
    static let multiLabel: Set<String> = [
        // Country codes.
        "co.uk", "org.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk", "ac.uk", "gov.uk", "nhs.uk", "police.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "asn.au", "id.au",
        "co.nz", "org.nz", "net.nz", "ac.nz", "govt.nz", "geek.nz",
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp", "ad.jp", "ed.jp", "gr.jp", "lg.jp",
        "co.kr", "or.kr", "ne.kr", "go.kr", "ac.kr", "re.kr",
        "com.br", "net.br", "org.br", "gov.br", "edu.br",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
        "co.in", "net.in", "org.in", "firm.in", "gen.in", "ind.in", "ac.in", "gov.in", "edu.in",
        "co.za", "org.za", "net.za", "gov.za", "ac.za", "web.za",
        "com.mx", "org.mx", "net.mx", "gob.mx", "edu.mx",
        "com.ar", "org.ar", "net.ar", "gob.ar", "edu.ar",
        "com.tr", "org.tr", "net.tr", "gov.tr", "edu.tr", "gen.tr",
        "com.tw", "org.tw", "net.tw", "gov.tw", "edu.tw", "idv.tw",
        "com.hk", "org.hk", "net.hk", "gov.hk", "edu.hk", "idv.hk",
        "com.sg", "org.sg", "net.sg", "gov.sg", "edu.sg",
        "com.my", "org.my", "net.my", "gov.my", "edu.my",
        "co.il", "org.il", "net.il", "ac.il", "gov.il",
        "co.id", "or.id", "ac.id", "go.id", "web.id",
        "co.th", "or.th", "ac.th", "go.th", "in.th",
        "com.ua", "org.ua", "net.ua", "gov.ua", "in.ua",
        "com.pl", "org.pl", "net.pl",
        "com.fr", "asso.fr", "gouv.fr",
        "com.es", "org.es", "nom.es", "gob.es", "edu.es",
        "com.eg", "gov.eg", "edu.eg",
        "com.sa", "gov.sa", "edu.sa",
        "com.ng", "org.ng", "gov.ng",
        "co.ke", "or.ke", "go.ke", "ac.ke",
        "com.pk", "org.pk", "gov.pk", "edu.pk",
        "com.vn", "gov.vn", "edu.vn",
        "com.ph", "gov.ph", "edu.ph",
        "com.pe", "gob.pe",
        "com.co", "gov.co", "edu.co",
        "com.uy", "gub.uy",
        // Hosting services.
        "github.io", "gitlab.io", "bitbucket.io", "githubusercontent.com", "readthedocs.io",
        "pages.dev", "workers.dev", "deno.dev", "fly.dev",
        "vercel.app", "netlify.app", "web.app", "firebaseapp.com", "onrender.com",
        "herokuapp.com", "appspot.com", "blogspot.com", "myshopify.com", "glitch.me",
        "azurewebsites.net", "cloudfront.net", "s3.amazonaws.com",
    ]
}
