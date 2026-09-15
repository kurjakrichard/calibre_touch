enum Bookkeys {
  id(name: 'id'),
  title(name: 'title'),
  author(name: 'author'),
  price(name: 'price'),
  image(name: 'image'),
  path(name: 'path'),
  filename(name: 'filename'),
  format(name: 'format'),
  // ignore: constant_identifier_names
  last_modified(name: 'last_modified'),
  description(name: 'description'),
  pages(name: 'pages'),
  rating(name: 'rating');

  const Bookkeys({
    required this.name,
  });

  final String name;
}

enum DbTypekeys {
  idType(name: 'INTEGER PRIMARY KEY AUTOINCREMENT'),
  stringType(name: 'TEXT NOT NULL'),
  integerType(name: 'INTEGER NOT NULL'),
  doubleType(name: 'REAl NOT NULL'),
  boolType(name: 'BOOLEAN NOT NULL');

  const DbTypekeys({
    required this.name,
  });

  final String name;
}

enum Routes {
  home(name: '/', path: '/home'),
  bookDetails(name: 'bookDetails', path: '/home/bookDetails'),
  desktopDetails(name: 'desktopDetails', path: '/home/desktopDetails'),
  firstRun(name: 'firstRun', path: '/firstRun'),
  splash(name: 'splash', path: '/splashPage'),
  updateBook(name: 'updateBook', path: '/home/updateBook'),
  updateBook2(name: 'updateBook2', path: '/updateBook2');

  const Routes({
    required this.name,
    required this.path,
  });

  final String name;
  final String path;
}

// ignore: camel_case_types
enum Formats {
  lrf,
  rar,
  zip,
  rtf,
  lit,
  txt,
  txtz,
  text,
  htm,
  xhtm,
  html,
  htmlz,
  xhtml,
  pdf,
  pdb,
  updb,
  pdr,
  prc,
  mobi,
  azw,
  doc,
  epub,
  fb2,
  fbz,
  djv,
  djvu,
  lrx,
  cbr,
  cb7,
  cbz,
  cbc,
  oebzip,
  rb,
  imp,
  odt,
  chm,
  tpz,
  azw1,
  pml,
  pmlz,
  mbp,
  tan,
  snb,
  xps,
  oxps,
  azw4,
  book,
  zbf,
  pobi,
  docx,
  docm,
  md,
  textile,
  markdown,
  ibook,
  ibooks,
  iba,
  azw3,
  ps,
  kepub,
  kfx,
  kpf;
}
