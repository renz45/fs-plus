fs = require 'fs'
Module = require 'module'
path = require 'path'

_ = require 'underscore-plus'
async = require 'async'
mkdirp = require 'mkdirp'
rimraf = require 'rimraf'

# Public: Useful extensions to node's built-in fs module
#
# Important, this extends Node's builtin in ['fs' module][fs], which means that you
# can do anything that you can do with Node's 'fs' module plus a few extra
# functions that we've found to be helpful.
#
# [fs]: http://nodejs.org/api/fs.html
fsPlus =
  getHomeDirectory: ->
    if process.platform is 'win32'
      process.env.USERPROFILE
    else
      process.env.HOME

  # Public: Make the given path absolute by resolving it against the current
  # working directory.
  #
  # relativePath - The {String} containing the relative path. If the path is
  #                prefixed with '~', it will be expanded to the current user's
  #                home directory.
  #
  # Returns the {String} absolute path or the relative path if it's unable to
  # determine its realpath.
  absolute: (relativePath) ->
    return null unless relativePath?

    homeDir = fsPlus.getHomeDirectory()

    if relativePath is '~'
      relativePath = homeDir
    else if relativePath.indexOf('~/') is 0
      relativePath = "#{homeDir}#{relativePath.substring(1)}"

    try
      fs.realpathSync(relativePath)
    catch e
      relativePath

  # Public: Is the given path absolute?
  #
  # pathToCheck - The relative or absolute {String} path to check.
  #
  # Returns a {Boolean}, true if the path is absolute, false otherwise.
  isAbsolute: (pathToCheck='') ->
    if process.platform is 'win32'
      pathToCheck[1] is ':' # C:\ style
    else
      pathToCheck[0] is '/' # /usr style

  # Public: Returns true if a file or folder at the specified path exists.
  existsSync: (pathToCheck) ->
    pathToCheck?.length > 0 and statSyncNoException(pathToCheck) isnt false

  # Public: Returns true if the given path exists and is a directory.
  isDirectorySync: (directoryPath) ->
    return false unless directoryPath?.length > 0
    if stat = statSyncNoException(directoryPath)
      stat.isDirectory()
    else
      false

  # Public: Asynchronously checks that the given path exists and is a directory.
  isDirectory: (directoryPath, done) ->
    return done(false) unless directoryPath?.length > 0
    fs.exists directoryPath, (exists) ->
      if exists
        fs.stat directoryPath, (error, stat) ->
          if error?
            done(false)
          else
            done(stat.isDirectory())
      else
        done(false)

  # Public: Returns true if the specified path exists and is a file.
  isFileSync: (filePath) ->
    return false unless filePath?.length > 0
    if stat = statSyncNoException(filePath)
      stat.isFile()
    else
      false

  # Public: Returns true if the specified path is a symbolic link.
  isSymbolicLinkSync: (symlinkPath) ->
    return false unless symlinkPath?.length > 0
    if stat = lstatSyncNoException(symlinkPath)
      stat.isSymbolicLink()
    else
      false

  # Public: Calls back with true if the specified path is a symbolic link.
  isSymbolicLink: (symlinkPath, callback) ->
    if symlinkPath?.length > 0
      fs.lstat symlinkPath, (error, stat) ->
        callback?(stat? and stat.isSymbolicLink())
    else
      process.nextTick -> callback?(false)

  # Public: Returns true if the specified path is executable.
  isExecutableSync: (pathToCheck) ->
    return false unless pathToCheck?.length > 0
    if stat = statSyncNoException(pathToCheck)
      (stat.mode & 0o777 & 1) isnt 0
    else
      false

  # Public: Returns the size of the specified path.
  getSizeSync: (pathToCheck) ->
    if pathToCheck?.length > 0
      statSyncNoException(pathToCheck).size ? -1
    else
      -1

  # Public: Returns an Array with the paths of the files and directories
  # contained within the directory path. It is not recursive.
  #
  # rootPath - The absolute {String} path to the directory to list.
  # extensions - An {Array} of extensions to filter the results by. If none are
  #              given, none are filtered (optional).
  listSync: (rootPath, extensions) ->
    return [] unless fsPlus.isDirectorySync(rootPath)
    paths = fs.readdirSync(rootPath)
    paths = fsPlus.filterExtensions(paths, extensions) if extensions
    paths = paths.map (childPath) -> path.join(rootPath, childPath)
    paths

  # Public: Asynchronously lists the files and directories in the given path.
  # The listing is not recursive.
  #
  # rootPath - The absolute {String} path to the directory to list.
  # extensions - An {Array} of extensions to filter the results by. If none are
  #              given, none are filtered (optional).
  # callback - The {Function} to call.
  list: (rootPath, rest...) ->
    extensions = rest.shift() if rest.length > 1
    done = rest.shift()
    fs.readdir rootPath, (error, paths) ->
      if error?
        done(error)
      else
        paths = fsPlus.filterExtensions(paths, extensions) if extensions
        paths = paths.map (childPath) -> path.join(rootPath, childPath)
        done(null, paths)

  # Returns only the paths which end with one of the given extensions.
  filterExtensions: (paths, extensions) ->
    extensions = extensions.map (ext) ->
      if ext is ''
        ext
      else
        '.' + ext.replace(/^\./, '')
    paths.filter (pathToCheck) ->
      _.include(extensions, path.extname(pathToCheck))

  # Public: Get all paths under the given path.
  #
  # rootPath - The {String} path to start at.
  #
  # Return an {Array} of {String}s under the given path.
  listTreeSync: (rootPath) ->
    paths = []
    onPath = (childPath) ->
      paths.push(childPath)
      true
    fsPlus.traverseTreeSync(rootPath, onPath, onPath)
    paths

  # Public: Moves the file or directory to the target synchronously.
  moveSync: (source, target) ->
    fs.renameSync(source, target)

  # Public: Removes the file or directory at the given path synchronously.
  removeSync: (pathToRemove) ->
    rimraf.sync(pathToRemove)

  # Public: Open, write, flush, and close a file, writing the given content
  # synchronously.
  #
  # It also creates the necessary parent directories.
  writeFileSync: (filePath, content, options) ->
    mkdirp.sync(path.dirname(filePath))
    fs.writeFileSync(filePath, content, options)

  # Public: Open, write, flush, and close a file, writing the given content
  # asynchronously.
  #
  # It also creates the necessary parent directories.
  writeFile: (filePath, content, options, callback) ->
    callback = _.last(arguments)
    mkdirp path.dirname(filePath), (error) ->
      if error?
        callback?(error)
      else
        fs.writeFile(filePath, content, options, callback)

  # Public: Copies the given path asynchronously.
  copy: (sourcePath, destinationPath, done) ->
    mkdirp path.dirname(destinationPath), (error) ->
      if error?
        done?(error)
        return

      sourceStream = fs.createReadStream(sourcePath)
      sourceStream.on 'error', (error) ->
        done?(error)
        done = null

      destinationStream = fs.createWriteStream(destinationPath)
      destinationStream.on 'error', (error) ->
        done?(error)
        done = null
      destinationStream.on 'close', ->
        done?()
        done = null

      sourceStream.pipe(destinationStream)

  # Public: Copies the given path recursively and synchronously.
  copySync: (sourcePath, destinationPath) ->
    mkdirp.sync(destinationPath)
    for source in fs.readdirSync(sourcePath)
      sourceFilePath = path.join(sourcePath, source)
      destinationFilePath = path.join(destinationPath, source)

      if fsPlus.isDirectorySync(sourceFilePath)
        fsPlus.copySync(sourceFilePath, destinationFilePath)
      else
        content = fs.readFileSync(sourceFilePath)
        fs.writeFileSync(destinationFilePath, content)

  # Public: Create a directory at the specified path including any missing
  # parent directories synchronously.
  makeTreeSync: (directoryPath) ->
    mkdirp.sync(directoryPath) unless fsPlus.existsSync(directoryPath)

  # Public: Recursively walk the given path and execute the given functions
  # synchronously.
  #
  # rootPath - The {String} containing the directory to recurse into.
  # onFile - The {Function} to execute on each file, receives a single argument
  #          the absolute path.
  # onDirectory - The {Function} to execute on each directory, receives a single
  #               argument the absolute path (defaults to onFile).
  traverseTreeSync: (rootPath, onFile, onDirectory=onFile) ->
    return unless fsPlus.isDirectorySync(rootPath)

    traverse = (directoryPath, onFile, onDirectory) ->
      for file in fs.readdirSync(directoryPath)
        childPath = path.join(directoryPath, file)
        stats = fs.lstatSync(childPath)
        if stats.isSymbolicLink()
          if linkStats = statSyncNoException(childPath)
            stats = linkStats
        if stats.isDirectory()
          traverse(childPath, onFile, onDirectory) if onDirectory(childPath)
        else if stats.isFile()
          onFile(childPath)

    traverse(rootPath, onFile, onDirectory)

  # Public: Recursively walk the given path and execute the given functions
  # asynchronously.
  #
  # rootPath - The {String} containing the directory to recurse into.
  # onFile - The {Function} to execute on each file, receives a single argument
  #          the absolute path.
  # onDirectory - The {Function} to execute on each directory, receives a single
  #               argument the absolute path (defaults to onFile).
  traverseTree: (rootPath, onFile, onDirectory, onDone) ->
    fs.readdir rootPath, (error, files) ->
      if error
        onDone?()
      else
        queue = async.queue (childPath, callback) ->
          fs.stat childPath, (error, stats) ->
            if error
              callback(error)
            else if stats.isFile()
              onFile(childPath)
              callback()
            else if stats.isDirectory()
              if onDirectory(childPath)
                fs.readdir childPath, (error, files) ->
                  if error
                    callback(error)
                  else
                    for file in files
                      queue.unshift(path.join(childPath, file))
                    callback()
              else
                callback()
        queue.concurrency = 1
        queue.drain = onDone
        queue.push(path.join(rootPath, file)) for file in files

  # Public: Hashes the contents of the given file.
  #
  # pathToDigest - The {String} containing the absolute path.
  #
  # Returns a String containing the MD5 hexadecimal hash.
  md5ForPath: (pathToDigest) ->
    contents = fs.readFileSync(pathToDigest)
    require('crypto').createHash('md5').update(contents).digest('hex')

  # Public: Finds a relative path among the given array of paths.
  #
  # loadPaths - An {Array} of absolute and relative paths to search.
  # pathToResolve - The {String} containing the path to resolve.
  # extensions - An {Array} of extensions to pass to {resolveExtensions} in
  #              which case pathToResolve should not contain an extension
  #              (optional).
  #
  # Returns the absolute path of the file to be resolved if it's found and
  # undefined otherwise.
  resolve: (args...) ->
    extensions = args.pop() if _.isArray(_.last(args))
    pathToResolve = args.pop()
    loadPaths = args

    if fsPlus.isAbsolute(pathToResolve)
      if extensions and resolvedPath = fsPlus.resolveExtension(pathToResolve, extensions)
        return resolvedPath
      else
        return pathToResolve if fsPlus.existsSync(pathToResolve)

    for loadPath in loadPaths
      candidatePath = path.join(loadPath, pathToResolve)
      if extensions
        if resolvedPath = fsPlus.resolveExtension(candidatePath, extensions)
          return resolvedPath
      else
        return fsPlus.absolute(candidatePath) if fsPlus.existsSync(candidatePath)
    undefined

  # Public: Like {.resolve} but uses node's modules paths as the load paths to
  # search.
  resolveOnLoadPath: (args...) ->
    loadPaths = Module.globalPaths.concat(module.paths)
    fsPlus.resolve(loadPaths..., args...)

  # Public: Finds the first file in the given path which matches the extension
  # in the order given.
  #
  # pathToResolve - The {String} containing relative or absolute path of the
  #                 file in question without the extension or '.'.
  # extensions - The ordered {Array} of extensions to try.
  #
  # Returns the absolute path of the file if it exists with any of the given
  # extensions, otherwise it's undefined.
  resolveExtension: (pathToResolve, extensions) ->
    for extension in extensions
      if extension == ""
        return fsPlus.absolute(pathToResolve) if fsPlus.existsSync(pathToResolve)
      else
        pathWithExtension = pathToResolve + "." + extension.replace(/^\./, "")
        return fsPlus.absolute(pathWithExtension) if fsPlus.existsSync(pathWithExtension)
    undefined

  # Public: Returns true for extensions associated with compressed files.
  isCompressedExtension: (ext) ->
    _.indexOf([
      '.gz'
      '.jar'
      '.tar'
      '.tgz'
      '.zip'
    ], ext, true) >= 0

  # Public: Returns true for extensions associated with image files.
  isImageExtension: (ext) ->
    _.indexOf([
      '.gif'
      '.ico'
      '.jpeg'
      '.jpg'
      '.png'
      '.tiff'
    ], ext, true) >= 0

  # Public: Returns true for extensions associated with pdf files.
  isPdfExtension: (ext) ->
    ext is '.pdf'

  # Public: Returns true for extensions associated with binary files.
  isBinaryExtension: (ext) ->
    _.indexOf([
      '.DS_Store'
      '.a'
      '.o'
      '.so'
      '.woff'
    ], ext, true) >= 0

  # Public: Returns true for files named similarily to 'README'
  isReadmePath: (readmePath) ->
    extension = path.extname(readmePath)
    base = path.basename(readmePath, extension).toLowerCase()
    base is 'readme' and (extension is '' or fsPlus.isMarkdownExtension(extension))

  # Public: Returns true for extensions associated with Markdown files.
  isMarkdownExtension: (ext) ->
    _.indexOf([
      '.markdown'
      '.md'
      '.mdown'
      '.mkd'
      '.mkdown'
      '.ron'
    ], ext, true) >= 0

{statSyncNoException, lstatSyncNoException} = fs
statSyncNoException ?= (args...) ->
  try
    fs.statSync(args...)
  catch error
    false

lstatSyncNoException ?= (args...) ->
  try
    fs.lstatSync(args...)
  catch error
    false

module.exports = _.extend({}, fs, fsPlus)
