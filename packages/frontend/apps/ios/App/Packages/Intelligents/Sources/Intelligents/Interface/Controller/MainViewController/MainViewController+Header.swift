//
//  MainViewController+Header.swift
//  Intelligents
//
//  Created by 秋星桥 on 6/19/25.
//

import UIKit

extension MainViewController: MainHeaderViewDelegate {
  func mainHeaderViewDidTapClose() {
    dismiss(animated: true)
  }

  func mainHeaderViewDidTapDropdown() {
    refreshHeaderModelBadge()
  }

  func mainHeaderViewDidTapMenu() {
    print(#function)
  }

  func refreshHeaderModelBadge() {
    guard let catalog = intelligentContext.currentModelCatalog else {
      headerView.updateModelBadge(title: nil, menu: nil)
      return
    }

    let selectedModelId = intelligentContext.currentSession?.model
    headerView.updateModelBadge(
      title: catalog.badgeTitle(for: selectedModelId),
      menu: nil
    )
  }
}
