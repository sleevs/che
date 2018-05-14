/*
 * Copyright (c) 2012-2018 Red Hat, Inc.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *   Red Hat, Inc. - initial API and implementation
 */
package org.eclipse.che.selenium.core.webdriver;

import java.io.IOException;
import java.util.List;

/**
 * This is set of methods to work with files which are downloaded into WebDriver.
 *
 * @author Dmytro Nochevnov
 */
public interface DownloadedFileUtil {

  /**
   * Unzips downloaded package to destination directory.
   *
   * @param webDriverSessionId ID of web driver session which holds downloaded package
   * @param downloadedPackageName downloaded package to unzip
   */
  List<String> getPackageFileList(String webDriverSessionId, String downloadedPackageName)
      throws IOException;

  /**
   * Obtains content of downloaded file.
   *
   * @param webDriverSessionId ID of web driver session which holds downloaded file
   * @param downloadedFileName downloaded file name
   * @return
   */
  List<String> getDownloadedFileContent(String webDriverSessionId, String downloadedFileName)
      throws IOException;

  /**
   * Removes downloaded file.
   *
   * @param webDriverSessionId ID of web driver session which holds downloaded file
   * @param filename downloaded file name
   */
  void removeDownloadedFile(String webDriverSessionId, String filename) throws IOException;
}
