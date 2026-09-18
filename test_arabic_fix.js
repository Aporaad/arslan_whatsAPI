// Test Arabic decoding function
function fixArabicEncoding(input) {
  if (!input || typeof input !== 'string') return input;

  // 1. Check if string already contains standard Arabic Unicode characters
  const hasArabicUnicode = /[\u0600-\u06FF]/.test(input);

  // 2. Check for UTF-8 Mojibake (Latin-1 / CP1252 misinterpretation of UTF-8)
  // e.g. "Ù…Ø±Ø­Ø¨Ø§" which is "مرحبا"
  if (/[\u00C0-\u00DF][\u0080-\u00BF]/.test(input)) {
    try {
      const decoded = Buffer.from(input, 'latin1').toString('utf8');
      if (/[\u0600-\u06FF]/.test(decoded)) {
        return decoded;
      }
    } catch {
      // ignore
    }
  }

  // 3. If there are NO Arabic Unicode chars, check for Windows-1256 bytes mapped to Latin-1
  if (!hasArabicUnicode && /[\u00C0-\u00FE]/.test(input)) {
    const cp1256Map = {
      0x81: 0x067E, 0x8D: 0x0686, 0x8E: 0x00E9, 0x8F: 0x06AF,
      0x90: 0x06AF, 0x98: 0x0698,
      0xC0: 0x0640, 0xC1: 0x0621, 0xC2: 0x0622, 0xC3: 0x0623, 0xC4: 0x0624, 0xC5: 0x0625,
      0xC6: 0x0626, 0xC7: 0x0627, 0xC8: 0x0628, 0xC9: 0x0629, 0xCA: 0x062A, 0xCB: 0x062B,
      0xCC: 0x062C, 0xCD: 0x062D, 0xCE: 0x062E, 0xCF: 0x062F, 0xD0: 0x0630, 0xD1: 0x0631,
      0xD2: 0x0632, 0xD3: 0x0633, 0xD4: 0x0634, 0xD5: 0x0635, 0xD6: 0x0636, 0xD8: 0x0637,
      0xD9: 0x0638, 0xDA: 0x0639, 0xDB: 0x063A, 0xDC: 0x0640, 0xDD: 0x0641, 0xDE: 0x0642,
      0xDF: 0x0643, 0xE1: 0x0644, 0xE3: 0x0645, 0xE4: 0x0646, 0xE5: 0x0647, 0xE6: 0x0648,
      0xE7: 0x0649, 0xE8: 0x064A, 0xEA: 0x064B, 0xEB: 0x064C, 0xEC: 0x064D, 0xED: 0x064E,
      0xEE: 0x064F, 0xEF: 0x0650, 0xF0: 0x0651, 0xF1: 0x0652
    };

    let converted = '';
    let arabicCount = 0;
    for (let i = 0; i < input.length; i++) {
      const code = input.charCodeAt(i);
      if (cp1256Map[code]) {
        converted += String.fromCharCode(cp1256Map[code]);
        arabicCount++;
      } else {
        converted += input[i];
      }
    }
    if (arabicCount > 0) {
      return converted;
    }
  }

  return input;
}

// Test cases
console.log('Test 1 (Already Arabic):', fixArabicEncoding('مرحبا بك'));
const mojibake = Buffer.from('مرحبا بك في نظام الواتساب', 'utf8').toString('latin1');
console.log('Test 2 (Mojibake UTF-8 as Latin1):', mojibake);
console.log('Test 2 Fixed:', fixArabicEncoding(mojibake));

// Test 3 Windows-1256 bytes for "مرحبا" (E3 D1 CD C8 C7)
const cp1256Text = String.fromCharCode(0xE3, 0xD1, 0xCD, 0xC8, 0xC7);
console.log('Test 3 (CP1256 chars):', cp1256Text);
console.log('Test 3 Fixed:', fixArabicEncoding(cp1256Text));
