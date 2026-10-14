# Bookbinder

Bookbinder is a small macOS app for PDF files. It has three tabs:

- **Extract**: Enter a page range and add it to the selection. Add more ranges as necessary.
  You can also click pages in the page list. Then save the selected pages as a new PDF.
- **Merge**: Merge PDF files and images into one PDF. Drag a row to change the order.
- **Booklet**: Put two A4 pages on each side of an A4 landscape sheet. The result is an A5 booklet.

To make a booklet:

1. Print the booklet PDF on two sides with short-edge binding.
2. Put the stack with page 1 on top.
3. Cut the stack in half.
4. Turn the right half over.
5. Put the right half below the left half.

For 4 pages, the front of the sheet shows pages 1 and 4. The back shows pages 3 and 2.

To build the app, run `./build.sh`. You need the Xcode command line tools.
