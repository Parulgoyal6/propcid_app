enum CreatableContent { video, property, article, project }

bool canCreate(CreatableContent content, String? userType) {
  switch (content) {
    case CreatableContent.video:
      return userType == 'influencer';
    case CreatableContent.project:
      return userType == 'builder';
    case CreatableContent.property:
    case CreatableContent.article:
      return userType != 'builder';
  }
}

String createDeniedMessage(CreatableContent content) {
  switch (content) {
    case CreatableContent.video:
      return 'Only influencer accounts can create videos.';
    case CreatableContent.project:
      return 'Only builder accounts can create projects.';
    case CreatableContent.property:
      return "Builder accounts manage projects, not property listings.";
    case CreatableContent.article:
      return "Builder accounts can't create articles.";
  }
}
