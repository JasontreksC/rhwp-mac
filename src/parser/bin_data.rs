//! BinData 스토리지 추출
//!
//! CFB 컨테이너의 BinData/ 스토리지에서 이미지 등 바이너리 데이터를 추출한다.
//! DocInfo의 BinData 목록과 매칭하여 실제 바이트 데이터를 제공한다.

use super::cfb_reader::CfbReader;

/// BinData 콘텐츠 (실제 바이너리 데이터)
#[derive(Debug, Clone)]
pub struct BinDataContent {
    /// 스토리지 내 파일명 (예: "BIN0001.jpg")
    pub storage_name: String,
    /// 바이너리 데이터
    pub data: Vec<u8>,
}

/// 특정 BinData ID에 해당하는 스토리지명 생성
///
/// DocInfo의 BinData 인덱스(0-based)를 BinData 스토리지명으로 변환.
/// HWP 규칙: BIN{XXXX}.{ext} (XXXX = ID+1, 4자리 0패딩)
pub fn bin_data_storage_name(bin_id: u16, extension: &str) -> String {
    format!("BIN{:04X}.{}", bin_id as u32 + 1, extension)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bin_data_storage_name() {
        assert_eq!(bin_data_storage_name(0, "jpg"), "BIN0001.jpg");
        assert_eq!(bin_data_storage_name(1, "png"), "BIN0002.png");
        assert_eq!(bin_data_storage_name(15, "bmp"), "BIN0010.bmp");
        assert_eq!(bin_data_storage_name(255, "gif"), "BIN0100.gif");
    }

    #[test]
    fn test_bin_data_content() {
        let content = BinDataContent {
            storage_name: "BIN0001.jpg".to_string(),
            data: vec![0xFF, 0xD8, 0xFF, 0xE0], // JPEG header
        };
        assert_eq!(content.storage_name, "BIN0001.jpg");
        assert_eq!(content.data.len(), 4);
    }
}
