import '../models/book_content.dart';
import '../models/book_file.dart';

/// The contract for turning a [BookFile] into ready-to-display
/// [BookContent], regardless of what format that file is.
///
/// WHY THIS INTERFACE EXISTS (this is the "extension point" the
/// architecture review specifically called out before Module 3 started):
/// Right now, exactly one class implements this — [PlainTextExtractor],
/// for `.txt` files. When PDF or EPUB support is added in a later
/// version, they become new classes that implement this SAME interface.
/// Nothing about [BookReaderController], the Reader screen's widgets, or
/// Module 4/5's TTS and highlighting code needs to change or even know
/// that a new format was added — they only ever depend on this abstract
/// contract, never on a concrete extractor.
///
/// WHY THIS LIVES IN `domain/`, NOT `data/`:
/// This file declares WHAT an extractor does, not HOW. It has zero
/// imports from `dart:io` or any third-party package. The concrete
/// implementations that actually touch the file system live in `data/`,
/// exactly like [BookImportService] does for importing.
abstract class TextExtractor {
  Future<BookContent> extract(BookFile book);
}
