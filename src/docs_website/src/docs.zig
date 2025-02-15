const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const LazyPath = std.Build.LazyPath;
const log = std.log.scoped(.docs);
const Website = @import("website.zig").Website;
const Html = @import("html.zig").Html;
const content = @import("./content.zig");

const base_path = "../../docs";

const SearchIndexEntry = struct {
    page_path: []const u8,
    html_path: LazyPath,
};
const SearchIndex = std.ArrayList(SearchIndexEntry);

pub fn build(
    b: *std.Build,
    output: *std.Build.Step.WriteFile,
    website: Website,
) !void {
    const arena = b.allocator;

    var search_index = SearchIndex.init(arena);

    var page_buffer: [1 << 16]u8 = undefined;
    var base = try std.fs.cwd().openDir(base_path, .{});
    defer base.close();
    const root_page = try content.load(arena, base, &page_buffer);

    try tree_install(b, website, output, &search_index, root_page, root_page);

    const run_search_index_writer = b.addRunArtifact(b.addExecutable(.{
        .name = "search_index_writer",
        .root_source_file = b.path("src/search_index_writer.zig"),
        .target = b.graph.host,
    }));
    for (search_index.items) |entry| {
        run_search_index_writer.addArg(entry.page_path);
        run_search_index_writer.addFileArg(entry.html_path);
    }
    _ = output.addCopyFile(
        run_search_index_writer.captureStdOut(),
        "search-index.json",
    );

    try write_404_page(b, website, output);
}

fn tree_install(
    b: *std.Build,
    website: Website,
    output: *std.Build.Step.WriteFile,
    search_index: *SearchIndex,
    root: content.Page,
    page: content.Page,
) !void {
    try page_install(b, website, output, search_index, root, page);
    for (page.children) |child| try tree_install(b, website, output, search_index, root, child);
}

fn page_install(
    b: *std.Build,
    website: Website,
    output: *std.Build.Step.WriteFile,
    search_index: *SearchIndex,
    root: content.Page,
    page: content.Page,
) !void {
    const page_html = run_pandoc(b, website.pandoc_bin, page.path);

    try search_index.append(.{
        .page_path = page_url(b.allocator, page),
        .html_path = page_html,
    });

    const title_suffix = "TigerBeetle Docs";
    const page_title = blk: {
        if (std.mem.eql(u8, page.content.title, title_suffix)) {
            break :blk page.content.title;
        }
        break :blk try std.mem.join(b.allocator, " | ", &.{ page.content.title, title_suffix });
    };

    const nav_html = try Html.create(b.allocator);
    try nav_fill(website, nav_html, root, page);

    const page_path = website.write_page(.{
        .title = page_title,
        .nav = nav_html.string(),
        .content = page_html,
    });
    _ = output.addCopyFile(page_path, b.pathJoin(&.{ page_url(b.allocator, page), "index.html" }));
}

fn page_url(arena: Allocator, page: content.Page) []const u8 {
    const url = cut_suffix(page.path, "/README.md") orelse cut_suffix(page.path, ".md").?;
    const client = cut_prefix(url, "../src/clients/") orelse return url;
    return std.mem.concat(arena, u8, &.{"./coding/clients/", client}) catch @panic("OOM");

}

fn nav_fill(website: Website, html: *Html, node: content.Page, target: content.Page) !void {
    try html.write("<ol>\n", .{});
    for (node.children, node.content.children) |node_child, content_child| {
        if (node_child.children.len > 0) {
            try html.write("<li>\n<details", .{});
            if (nav_contains(node_child, target)) try html.write(" open", .{});
            try html.write("><summary class=\"item\">", .{});
            try html.write(
                \\<a href="$url_prefix/$url/">$title</a>
            , .{
                .url_prefix = website.url_prefix,
                .url = page_url(html.arena, node_child),
                // Fabio: index page titles are too long
                .title = content_child.title,
            });
            try html.write("</summary>\n", .{});
            try nav_fill(website, html, node_child, target);
            try html.write("</details></li>\n", .{});
        } else {
            try html.write(
                \\<li class="item"><a href="$url_prefix/$url/"$class>$title</a></li>
                \\
            , .{
                .url_prefix = website.url_prefix,
                .url = page_url(html.arena, node_child),
                .class = if (nave_same_page(node_child, target)) " class=\"target\"" else "",
                .title = content_child.title,
            });
        }
    }
    try html.write("</ol>\n", .{});
}

fn nav_contains(node: content.Page, target: content.Page) bool {
    if (nave_same_page(node, target)) return true;
    for (node.children) |child| {
        if (nav_contains(child, target)) return true;
    }
    return false;
}

fn nave_same_page(a: content.Page, b: content.Page) bool {
    return std.mem.eql(u8, a.path, b.path);
}

fn run_pandoc(b: *std.Build, pandoc_bin: std.Build.LazyPath, source: []const u8) std.Build.LazyPath {
    const pandoc_step = std.Build.Step.Run.create(b, "run pandoc");
    pandoc_step.addFileArg(pandoc_bin);
    pandoc_step.addArgs(&.{ "--from", "gfm+smart", "--to", "html5" });
    pandoc_step.addPrefixedFileArg("--lua-filter=", b.path("pandoc/markdown-links.lua"));
    pandoc_step.addPrefixedFileArg("--lua-filter=", b.path("pandoc/anchor-links.lua"));
    pandoc_step.addPrefixedFileArg("--lua-filter=", b.path("pandoc/table-wrapper.lua"));
    pandoc_step.addPrefixedFileArg("--lua-filter=", b.path("pandoc/code-block-buttons.lua"));
    pandoc_step.addPrefixedFileArg("--lua-filter=", b.path("pandoc/edit-link-footer.lua"));
    const result = pandoc_step.addPrefixedOutputFileArg("--output=", "pandoc-out.html");
    pandoc_step.addFileArg(b.path(base_path).path(b, source));
    return result;
}

fn write_404_page(
    b: *std.Build,
    website: Website,
    docs: *std.Build.Step.WriteFile,
) !void {
    const template = @embedFile("html/404.html");
    var html = try Html.create(b.allocator);
    try html.write(template, .{
        .url_prefix = website.url_prefix,
        .title = "Page not found | TigerBeetle Docs",
        .author = "TigerBeetle Team",
    });
    _ = docs.add("404.html", html.string());
}

pub fn cut(haystack: []const u8, needle: []const u8) ?struct { []const u8, []const u8 } {
    const index = std.mem.indexOf(u8, haystack, needle) orelse return null;

    return .{ haystack[0..index], haystack[index + needle.len ..] };
}

pub fn cut_prefix(text: []const u8, comptime prefix: []const u8) ?[]const u8 {
    return if (std.mem.startsWith(u8, text, prefix))
        text[prefix.len..]
    else
        null;
}

pub fn cut_suffix(text: []const u8, comptime suffix: []const u8) ?[]const u8 {
    return if (std.mem.endsWith(u8, text, suffix))
        text[0 .. text.len - suffix.len]
    else
        null;
}
