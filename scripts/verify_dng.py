"""Independently validate the actual Swift writer with TIFF parsing and LibRaw."""
import sys
import numpy as np
import tifffile
import rawpy

path = sys.argv[1]
y, x, c = np.indices((129, 96, 3), dtype=np.uint32)
expected = ((y * 997 + x * 37 + c * 10007) % 65536).astype(np.uint16)
with tifffile.TiffFile(path) as file:
    root = file.pages[0]
    assert root.photometric == 2 and root.bitspersample == 8
    assert root.asarray().shape[2] == 3
    assert 330 in root.tags and len(root.pages) == 1
    page = root.pages[0]
    tags = page.tags
    assert root.tags[50706].value == bytes([1, 4, 0, 0])
    assert root.tags[50707].value == bytes([1, 3, 0, 0])
    assert tags[262].value == 34892, "Not a LinearRaw DNG"
    assert tags[258].value == (16, 16, 16)
    assert tags[274].value == 1
    assert len(tags[273].value) == 3 and len(tags[279].value) == 3
    assert tags[50717].value == (65535, 65535, 65535)
    assert root.tags[50778].value == 21  # D65, matching the Rec.2020 matrix.
    matrix = np.array(root.tags[50721].value).reshape(9, 2)
    matrix = (matrix[:, 0] / matrix[:, 1]).reshape(3, 3)
    rec2020_to_xyz = np.array([[0.636958048, 0.144616904, 0.168880975],
                              [0.262700212, 0.677998072, 0.059301716],
                              [0, 0.028072693, 1.060985058]])
    np.testing.assert_allclose(matrix @ rec2020_to_xyz, np.eye(3), atol=0.000002)
    np.testing.assert_array_equal(page.asarray(), expected)
with rawpy.imread(path) as raw:
    assert raw.sizes.width == 96 and raw.sizes.height == 129
    decoded = raw.postprocess(output_bps=16, no_auto_bright=True,
        gamma=(1, 1), user_wb=[1, 1, 1, 1], output_color=rawpy.ColorSpace.raw,
        user_flip=0, no_auto_scale=True, user_black=0, user_sat=65535)
    assert decoded.shape == expected.shape
    np.testing.assert_allclose(decoded, expected, atol=2)
print("DNG verified: tags, Rec.2020 matrix, strips, RGB16 pixel identity, LibRaw decoding")
