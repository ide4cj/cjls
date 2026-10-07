package cjls

import std.collection.ArrayList
import std.fs.{File, FileInfo, Path, exists}
import std.io.OutputStream
import std.sort.sort
import rope.Rope
import loupe.vfs.{VfsPath, readFiles, readRoots}
import cjformat.formatText

/**
 * Formats the Cangjie files at `paths` in place, or with `check` only names those it would change;
 * a directory stands for the files the server would read in it (`readRoots`). Each file changed,
 * or to be, goes to `out` on a line, a file with syntax errors to `err`, left alone.
 *
 * @return the exit code: `1` if a path is not there or a file has syntax errors, or with `check`
 * if one is to change
 */
func formatPaths(paths: Array<Path>, check: Bool, out: OutputStream, err: OutputStream): Int64 {
    var failed = false
    for (path in paths where !exists(path)) {
        err.write("${path}: no such file or directory\n".toArray())
        failed = true
    }
    for ((path, rope) in sourcesAt(paths)) {
        let text = rope.toString()
        match (formatText(text)) {
            case None =>
                err.write("${path}: not formatted: it has syntax errors\n".toArray())
                failed = true
            case Some(formatted) where formatted != text =>
                if (check) {
                    failed = true
                } else {
                    File.writeTo(path.filePath.getOrThrow(), formatted.toArray())
                }
                out.write("${path}\n".toArray())
            case _ => ()
        }
    }
    out.flush()
    err.flush()
    if (failed) { 1 } else { 0 }
}

/**
 * The files at `paths`, a directory's read as the server reads it, in the order of their paths.
 */
func sourcesAt(paths: Array<Path>): Array<(VfsPath, Rope)> {
    let directories = paths.filter {path => isDirectory(path)}.map {path => VfsPath.file(path)}
    let files = paths.filter {path => !isDirectory(path)}.map {path => VfsPath.file(path)}
    let read = ArrayList<(VfsPath, Rope)>(readRoots(directories).files)
    read.add(all: readFiles(files).files)
    let sources = read.toArray()
    sort(sources, by: {a, b => a[0].toString().compare(b[0].toString())})
    sources
}

func isDirectory(path: Path): Bool {
    exists(path) && FileInfo(path).isDirectory()
}
