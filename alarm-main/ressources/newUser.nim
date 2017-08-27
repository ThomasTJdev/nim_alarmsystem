import
  os, md5, random, math, bcrypt

proc randomSalt(): string =
  result = ""
  for i in 0..127:
    var r = random(225)
    if r >= 32 and r <= 126:
      result.add(chr(random(225)))

proc devRandomSalt(): string =
  when defined(posix):
    result = ""
    var f = open("/dev/urandom")
    var randomBytes: array[0..127, char]
    discard f.readBuffer(addr(randomBytes), 128)
    for i in 0..127:
      if ord(randomBytes[i]) >= 32 and ord(randomBytes[i]) <= 126:
        result.add(randomBytes[i])
    f.close()
  else:
    result = randomSalt()

proc makeSalt*(): string =
  ## Creates a salt using a cryptographically secure random number generator.
  ##
  ## Ensures that the resulting salt contains no ``\0``.
  try:
    result = devRandomSalt()
  except IOError:
    result = randomSalt()

  var newResult = ""
  for i in 0 .. <result.len:
    if result[i] != '\0':
      newResult.add result[i]
  return newResult

proc makePassword*(password, salt: string, comparingTo = ""): string =
  ## Creates an MD5 hash by combining password and salt.
  when defined(windows):
    result = getMD5(salt & getMD5(password))
  else:
    let bcryptSalt = if comparingTo != "": comparingTo else: genSalt(8)
    result = hash(getMD5(salt & getMD5(password)), bcryptSalt)
