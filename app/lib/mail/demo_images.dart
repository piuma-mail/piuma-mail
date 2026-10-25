import 'dart:convert';
import 'dart:typed_data';

/// Small gradients standing in for a newsletter's photos in the demo inbox
/// (the `PhonePrivacy` mockup's living room, throw and lamp).
final demoImages = <String, Uint8List>{
  'https://cdn.bottegalume.example/autumn/living-room.jpg': _hero,
  'https://cdn.bottegalume.example/autumn/throw.jpg': _throw,
  'https://cdn.bottegalume.example/autumn/lamp.jpg': _lamp,
};

final _hero = base64Decode(
  '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'
  'T08z/arX6XdaV7nQAAAABJRU5ErkJggg==',
);

final _throw = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAABL0lEQVR42rXMCSuDAQAG4P'
  'e3fLu+nQizzQ7b7LDNZjZsTSISkUjkXHOttZIkSVKSJElK7vvKfV/5N37F+/yAB3/ZxG8m'
  '/pOOfU/UfI1VfY5EP1KR92T4bbjidTD00h987gs89fofe3wP3d77Ls9dp/u2w3XT7rxuc1'
  'y12i9bbBfN1vMmy1mj+bTBdFJvPK4zHNXqDxOFB/GC/Vg+qPtedR6o+240F9R9J5ID6r5d'
  'qQN13wrrQN03Q1pQ942gFtR9vVwD6r4W0IC6r/rVoO4rPjWo+3KZCtR9yasCdV/0KEHdF9'
  'xKUPd5lwjqPlcqgrrPOkVQ9xmHAtR92q4AdZ8qkYO6T9rkoO5ZqwzUPWORgbqnzVJQ9/Fi'
  'Kaj7qEkC6p4ySkDdkwYB1H2oSAB1H9AL/9tRDNAfW9c/AAAAAElFTkSuQmCC',
);

final _lamp = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAEjElEQVR42rWSSU9bZxiFv1'
  '/UVk3TJs1EQnEhDPHEYGzsa4yNR2zjCRs8MhhTYrBxCwEcpgRBk2ZsEyUhUUQlkg5RVaTS'
  'RdtFpXbTXf9BH2TJsiCh2Vg6i/O+73POvdey0Dr0byOdU693GQx9EsIwvmVQaGy6I0SR0W'
  '0095usAbMjaHGG9oVhZMkJ4OgG0dGrfa20dl23W7L6e1wDvf2DtkDMMZBwhpMuhGFkyQkA'
  'DPhNPaLNojmsLkeX2dvNy/qG7DTGRjypdP9oxjc24UcYRpacAMCAiby2SrT2dByQzq6zeI'
  '3uAUso5oiNuKn7LBucyoXzM5FCYRBhGFlyAgADJkLwcJtQmdor1dnb2eOW+kKWgbgjOebJ'
  'TAZy+fDsbHRxIbFcTK0uDSMMI0tOAGDARAgSP1AolMbWstSmdsnZ5fCbglF7YtQ9MRmYKU'
  'QW5+Nry8Ob19K3NjJ3NicQhpElJwAwYCIEiVNS2SnkBnVZGovG7Ja8YctQ0jU+4cvPhIsL'
  '8fXV0dubEw9uZZ/cyz37Oo8wjCw5AYABEyFInJLKTnFJryxJblB1WTtt/cbAkDU16s5OBa'
  '/MRa+vjPDKj+9ObT8sfPd07tXzeYRhZMkJAAyYCEHilFBVrhXNOkVJSkltsGud/u5wzD46'
  '7s3nB5YWEjeupx/eylL36vnC3ovl335YQxhGlpwAwICJECROCVXlWtGklZeklFSSXevymy'
  'JxezrTX5gJrxST/NxP7k2/3Jr7ZWfpz5/W/9m7gTCMLDkBgAETIUhc2n+AqlwrGjUtJSkM'
  'SoOt0+nrjsTs6XEvmdVi8vZGZuve9PdP5359sfzX7sa/v99GGEaWnABWSw8Y9xIkTglV5V'
  'rR0NFc0iWdvKu3w+6VQkPW0TFPPhdaWojfXE8/upPdefzF7rfFP3689vfuBsIwsuQEAAZM'
  'hCBxSqgq14r6tsaSeJrG1Grp6/INmBPDrsuX/fOzQ+srw/e/nHh2P/dya/bn7cW9nSWEYW'
  'TJCQAMmAhB4pRQVa4VMvXFslQGpWTTuHzGSNQ2lt7/iKvzsc21EYq27k5vP5jZefQ5wjCy'
  '5AQABkyEIHFKKjtFnaqhrCZNM883u3TeoCmasGcy3plcqHglur6c+mo9TeM3NycRhpElJw'
  'AwYCIEiVNS2SlqFZ+W9YmyXq69pDO3WfmhQj1R/k5pz3Q2MFeIXL0SXS0mri8lEYaRJScA'
  'MGAiBIlTUtkpLshllZKp6hW6/Wf08h2B7shQb2rYOT7uyU7681PBQi6EMIwsOQGAARMhSP'
  'xAoahpqTsg2f53tHR2q012jcOj7w+awoOWaNyWTDloRBhGlpwAwICJEDzcJs411R5Wrbyu'
  'qb1RrZfrelpNNo21T+f0Gtw+yRswIgwjS04AYMBEXlslzjReeJPqFDKSSm1Lu6TQmtR6c6'
  'vB0oYwjCw5AYAdUSJON9QcrfPNtTKFrEFd39R2sbm9EWEYWXL637g4VX+uqhInZWerKnGi'
  '7nRVJT6sPVVViePnT1ZV4ljNiapKvH/2o6pKvHfmeFUl3j31QVUl3vn4WFX1HzsPbNGc+4'
  'ZDAAAAAElFTkSuQmCC',
);
