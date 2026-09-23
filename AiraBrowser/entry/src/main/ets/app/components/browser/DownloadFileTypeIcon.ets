import { DownloadFileType } from '../../../core/download/DownloadFileTypeResolver';

export function resolveDownloadFileTypeImage(fileType: DownloadFileType): Resource {
  switch (fileType) {
    case 'archive':
      return $r('app.media.app_download_file_type_archive');
    case 'video':
      return $r('app.media.app_download_file_type_video');
    case 'audio':
      return $r('app.media.app_download_file_type_audio');
    case 'image':
      return $r('app.media.app_download_file_type_image');
    case 'pdf':
      return $r('app.media.app_download_file_type_pdf');
    case 'document':
      return $r('app.media.app_download_file_type_word');
    case 'spreadsheet':
      return $r('app.media.app_download_file_type_excel');
    case 'presentation':
      return $r('app.media.app_download_file_type_ppt');
    case 'web':
      return $r('app.media.app_download_file_type_web');
    case 'json':
      return $r('app.media.app_download_file_type_json');
    case 'apk':
      return $r('app.media.app_download_file_type_apk');
    case 'hap':
      return $r('app.media.app_download_file_type_hap');
    case 'text':
      return $r('app.media.app_download_file_type_text');
    default:
      return $r('app.media.app_download_file_type_unknown');
  }
}
