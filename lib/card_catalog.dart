class CardInfo {
  const CardInfo(this.id, this.name, this.description, {this.imagePath});
  final String id;
  final String name;
  final String description;
  final String? imagePath;
}

const cardCatalog = <CardInfo>[
  CardInfo(
    'bang',
    'BANG!',
    'Tấn công một người chơi trong tầm, gây 1 sát thương.',
    imagePath: 'assets/images/cards/bang.png',
  ),
  CardInfo(
    'dodge',
    'NÉ',
    'Tránh một lá BANG hoặc đòn tấn công cho phép NÉ.',
    imagePath: 'assets/images/cards/ne.png',
  ),
  CardInfo(
    'gatling',
    'GATLING',
    'Tất cả người chơi khác phải NÉ hoặc mất 1 máu.',
    imagePath: 'assets/images/cards/gatling.png',
  ),
  CardInfo(
    'indiani',
    'INDIANI',
    'Tất cả đối thủ phải đánh BANG để phòng thủ, nếu không mất 1 máu.',
    imagePath: 'assets/images/cards/indiani.png',
  ),
  CardInfo(
    'beer',
    'BEER',
    'Hồi 1 máu cho người sử dụng.',
    imagePath: 'assets/images/cards/beer.png',
  ),
  CardInfo(
    'saloon',
    'SALOON',
    'Hồi 1 máu cho mọi người chơi còn sống.',
    imagePath: 'assets/images/cards/saloon.png',
  ),
  CardInfo(
    'panico',
    'PANICO',
    'Lấy ngẫu nhiên một lá bài hoặc trang bị của người ở khoảng cách 1.',
    imagePath: 'assets/images/cards/panico.png',
  ),
  CardInfo(
    'cat_balou',
    'CAT BALOU',
    'Chọn và hủy một lá bài hoặc trang bị của người chơi khác.',
    imagePath: 'assets/images/cards/cat_balou.png',
  ),
  CardInfo(
    'dilizenza',
    'DILIZENZA',
    'Rút thêm 2 lá từ bộ bài chung.',
    imagePath: 'assets/images/cards/dilizenza.png',
  ),
  CardInfo(
    'wells_fargo',
    'WELLS FARGO',
    'Rút thêm 3 lá từ bộ bài chung.',
    imagePath: 'assets/images/cards/wells_fargo.png',
  ),
  CardInfo(
    'general_store',
    'GENERAL STORE',
    'Mở số lá bằng số người sống; mỗi người lần lượt lấy một lá.',
    imagePath: 'assets/images/cards/general_store.png',
  ),
  CardInfo(
    'duello',
    'DUELLO',
    'Hai người luân phiên đánh BANG; người không đánh được sẽ mất 1 máu.',
    imagePath: 'assets/images/cards/duello.png',
  ),
  CardInfo(
    'volcanic',
    'VOLCANIC',
    'Tầm bắn 1 nhưng cho phép dùng nhiều BANG trong lượt.',
    imagePath: 'assets/images/cards/volcanic.png',
  ),
  CardInfo(
    'gun_2',
    'SÚNG TẦM 2',
    'Tấn công mục tiêu ở khoảng cách tối đa 2.',
    imagePath: 'assets/images/cards/gun_range_2.png',
  ),
  CardInfo(
    'gun_3',
    'SÚNG TẦM 3',
    'Tấn công mục tiêu ở khoảng cách tối đa 3.',
    imagePath: 'assets/images/cards/gun_range_3.png',
  ),
  CardInfo(
    'gun_4',
    'SÚNG TẦM 4',
    'Tấn công mục tiêu ở khoảng cách tối đa 4.',
    imagePath: 'assets/images/cards/gun_range_4.png',
  ),
  CardInfo(
    'gun_5',
    'SÚNG TẦM 5',
    'Tấn công mục tiêu ở khoảng cách tối đa 5.',
    imagePath: 'assets/images/cards/gun_range_5.png',
  ),
  CardInfo(
    'mustang',
    'MUSTANG',
    'Khoảng cách từ người khác đến bạn tăng thêm 1.',
    imagePath: 'assets/images/cards/mustang.png',
  ),
  CardInfo(
    'appaloosa',
    'APPALOOSA',
    'Khoảng cách từ bạn đến người khác giảm 1.',
    imagePath: 'assets/images/cards/appaloosa.png',
  ),
  CardInfo(
    'barrel',
    'BARREL',
    'Khi bị BANG, phán xét Cơ để tự động NÉ.',
    imagePath: 'assets/images/cards/barrel.png',
  ),
  CardInfo(
    'jail',
    'JAIL',
    'Đặt lên người khác trừ Cảnh sát trưởng; có thể khiến họ mất lượt.',
    imagePath: 'assets/images/cards/jail.png',
  ),
  CardInfo(
    'dynamite',
    'DYNAMITE',
    'Đầu lượt có thể nổ theo phán xét Bích 2–9, gây 3 sát thương.',
    imagePath: 'assets/images/cards/dynamite.png',
  ),
];
